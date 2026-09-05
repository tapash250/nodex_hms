/// NODEX Enterprise HMS entry point.
///
/// Performs the bootstrap sequence described in `lib/app/app.dart` and installs
/// the provider overrides that constitute the composition root. Nothing here
/// contains clinical logic: it wires infrastructure and hands control to the
/// application widget.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:logging/logging.dart';
import 'package:nodex_hms/app/app.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/config/nodex_environment.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/data/local/local_database.dart';
import 'package:nodex_hms/data/remote/supabase_gateway.dart';
import 'package:nodex_hms/data/sync/backend_connector.dart';
import 'package:nodex_hms/domain/session/session_state.dart';
import 'package:nodex_hms/features/session/session_controller.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Route framework log records to the console only in debug builds. Release
  // builds attach the redacting NODEX sinks instead, so no PHI can reach a
  // general-purpose log.
  if (kDebugMode) {
    Logger.root.level = Level.INFO;
  } else {
    Logger.root.level = Level.WARNING;
  }

  final NodexEnvironment environment;
  try {
    environment = NodexEnvironment.resolve();
  } on NodexError catch (error) {
    runApp(
      BootstrapFailureApp(
        title: 'Configuration error',
        message:
            'This build is not configured correctly and cannot be used for '
            'clinical work.',
        detail: error.message,
      ),
    );
    return;
  }

  try {
    await Supabase.initialize(
      url: environment.supabaseUrl,
      publishableKey: environment.supabasePublishableKey,
      authOptions: const FlutterAuthClientOptions(
        // Sessions persist so a device that loses connectivity mid-shift can
        // continue within its offline authorization window.
        autoRefreshToken: true,
      ),
    );
  } on Object catch (error) {
    runApp(
      BootstrapFailureApp(
        title: 'Cannot reach the clinical backend',
        message:
            'The application could not initialise its connection to the '
            'clinical backend. Check the device network and the build '
            'configuration.',
        detail: '$error',
      ),
    );
    return;
  }

  // Device identity is resolved before the container is built so that every
  // provider sees a fully-populated composition root; the authorization snapshot
  // is bound to this fingerprint.
  final SessionDevice device = await _resolveDevice();

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      environmentProvider.overrideWithValue(environment),
      supabaseClientProvider.overrideWithValue(Supabase.instance.client),
      sessionDeviceProvider.overrideWithValue(device),
    ],
  );

  final NodexLogger logger = container.read(loggerProvider);

  final LocalDatabase localDatabase = container.read(localDatabaseProvider);
  try {
    await localDatabase.open();
  } on NodexError catch (error) {
    logger.critical(
      'bootstrap',
      'Local clinical database unavailable; refusing to start.',
      operation: 'bootstrap.open_database',
      outcome: 'failed',
      errorCode: error.code,
    );
    runApp(
      BootstrapFailureApp(
        title: 'Secure storage unavailable',
        message:
            'The encrypted local clinical database could not be opened, so '
            'clinical data cannot be stored safely on this device.',
        detail: error.message,
      ),
    );
    return;
  }

  // Replication is optional at build time: a build made before a PowerSync
  // instance exists is local-only rather than broken.
  if (environment.isSyncConfigured) {
    final SupabaseGateway gateway = container.read(supabaseGatewayProvider);
    unawaited(
      localDatabase.connect(
        connector: NodexBackendConnector(
          gateway: gateway,
          logger: logger,
          powerSyncUrl: environment.powerSyncUrl,
        ),
      ),
    );
  } else {
    logger.warning(
      'bootstrap',
      'No replication endpoint is configured; running local-only.',
      operation: 'bootstrap.connect_sync',
      outcome: 'skipped',
    );
  }

  logger.info(
    'bootstrap',
    'Application bootstrap complete.',
    operation: 'bootstrap',
    outcome: 'succeeded',
    dimensions: <String, Object?>{
      'environment': environment.environment.name,
      'sync_configured': environment.isSyncConfigured,
      'form_factor': device.formFactor.wireValue,
    },
  );

  runApp(
    UncontrolledProviderScope(container: container, child: const NodexApp()),
  );
}

/// Resolves device identity and form factor for snapshot binding and layout.
///
/// The fingerprint must be stable across launches, because the server binds an
/// authorization snapshot to it. Android's `id` is used, with a documented
/// fallback so a device that withholds it still enrols rather than failing.
Future<SessionDevice> _resolveDevice() async {
  final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  final PackageInfo packageInfo = await PackageInfo.fromPlatform();

  try {
    final AndroidDeviceInfo android = await deviceInfo.androidInfo;
    return SessionDevice(
      fingerprint: _composeFingerprint(android),
      formFactor: _classifyFormFactor(android),
      displayName: android.model,
      osVersion:
          'Android ${android.version.release} (SDK ${android.version.sdkInt})',
      appVersion: '${packageInfo.version}+${packageInfo.buildNumber}',
    );
  } on Object {
    // Without a platform identifier the device cannot be uniquely enrolled, so a
    // deterministic per-install value is used. The server treats it as a distinct
    // device, which is the safe interpretation.
    return SessionDevice(
      fingerprint: 'unidentified-${packageInfo.buildSignature}',
      formFactor: DeviceFormFactor.other,
      appVersion: '${packageInfo.version}+${packageInfo.buildNumber}',
    );
  }
}

String _composeFingerprint(AndroidDeviceInfo android) {
  final String id = android.id;
  if (id.isNotEmpty) {
    return '${android.manufacturer}:${android.model}:$id';
  }
  return '${android.manufacturer}:${android.model}:${android.fingerprint}';
}

/// Classifies the device against the specification's target form factors.
///
/// Smallest-width buckets follow Android's own tablet threshold: 600dp for a
/// compact tablet, 840dp for a large clinical tablet.
DeviceFormFactor _classifyFormFactor(AndroidDeviceInfo android) {
  final ui.FlutterView? view =
      WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
  if (view == null) {
    return DeviceFormFactor.other;
  }

  final double devicePixelRatio = view.devicePixelRatio;
  if (devicePixelRatio <= 0) {
    return DeviceFormFactor.other;
  }

  final double shortestSideDp =
      view.physicalSize.shortestSide / devicePixelRatio;

  if (shortestSideDp >= 840) {
    return DeviceFormFactor.tabletLarge;
  }
  if (shortestSideDp >= 600) {
    return DeviceFormFactor.tabletCompact;
  }
  return DeviceFormFactor.phone;
}
