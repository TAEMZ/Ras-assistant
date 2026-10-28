import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:torch_light/torch_light.dart';
import 'package:url_launcher/url_launcher.dart';

class NativeActionService {
  static const MethodChannel _channel = MethodChannel('com.voice.amharic.assistant/native_actions');

  VoidCallback? onWakeWordTriggered;
  void Function(Uint8List pcmBytes)? onWakeWordCandidate;
  void Function(String suiteName)? onRunTests;
  void Function(String query, bool isFromChat)? onTestQuery;

  NativeActionService() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onWakeWordTriggered') {
        debugPrint('[WAKE_WORD] Native wake-word triggered!');
        onWakeWordTriggered?.call();
      } else if (call.method == 'onWakeWordCandidate') {
        final Uint8List pcmBytes = call.arguments as Uint8List;
        debugPrint('[WAKE_WORD] Received candidate audio (${pcmBytes.length} bytes)');
        onWakeWordCandidate?.call(pcmBytes);
      } else if (call.method == 'runTests') {
        final suite = call.arguments?.toString() ?? 'full58';
        onRunTests?.call(suite);
      } else if (call.method == 'onTestQuery') {
        final args = call.arguments as Map<dynamic, dynamic>;
        final query = args['query']?.toString() ?? '';
        final isFromChat = args['isFromChat'] == true;
        onTestQuery?.call(query, isFromChat);
      }
    });
  }

  Future<bool> startBackgroundWakeService() async {
    try {
      final res = await _channel.invokeMethod<bool>('startBackgroundService');
      return res ?? false;
    } catch (e) {
      debugPrint('Error starting background wake service: $e');
      return false;
    }
  }

  Future<bool> stopBackgroundWakeService() async {
    try {
      final res = await _channel.invokeMethod<bool>('stopBackgroundService');
      return res ?? false;
    } catch (e) {
      debugPrint('Error stopping background wake service: $e');
      return false;
    }
  }

  Future<bool> confirmWakeWord() async {
    try {
      final res = await _channel.invokeMethod<bool>('confirmWakeWord');
      return res ?? false;
    } catch (e) {
      debugPrint('Error confirming wake word: $e');
      return false;
    }
  }

  bool _isTorchOn = false;
  bool get isTorchOn => _isTorchOn;

  List<Contact> _cachedContacts = [];
  List<Contact> get cachedContacts => _cachedContacts;

  List<Map<String, String>> _cachedApps = [];
  List<Map<String, String>> get cachedApps => _cachedApps;

  Future<bool> checkOverlayPermission() async {
    try {
      final res = await _channel.invokeMethod<bool>('checkOverlayPermission');
      return res ?? true;
    } catch (e) {
      return true;
    }
  }

  Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } catch (e) {
      debugPrint('Error requesting overlay permission: $e');
    }
  }

  Future<bool> requestAllPermissions() async {
    final micStatus = await Permission.microphone.request();
    final contactsStatus = await Permission.contacts.request();
    await Permission.phone.request();
    await Permission.camera.request();
    await Permission.notification.request();

    // Request storage/media permissions upfront
    await Permission.storage.request();
    await Permission.photos.request();
    await Permission.videos.request();
    await Permission.audio.request();

    final hasOverlay = await checkOverlayPermission();
    if (!hasOverlay) {
      await requestOverlayPermission();
    }

    // Request MANAGE_EXTERNAL_STORAGE for full file access (Android 11+)
    final hasStorage = await checkStoragePermission();
    if (!hasStorage) {
      debugPrint('[NativeActionService] Requesting MANAGE_EXTERNAL_STORAGE...');
      await requestStoragePermission();
    } else {
      debugPrint('[NativeActionService] MANAGE_EXTERNAL_STORAGE already granted');
    }

    return micStatus.isGranted && (contactsStatus.isGranted || contactsStatus.isLimited);
  }

  Future<bool> checkStoragePermission() async {
    try {
      final res = await _channel.invokeMethod<bool>('checkStoragePermission');
      return res ?? true;
    } catch (e) {
      debugPrint('Error checking storage permission: $e');
      return true;
    }
  }

  Future<void> requestStoragePermission() async {
    try {
      await _channel.invokeMethod('requestStoragePermission');
    } catch (e) {
      debugPrint('Error requesting storage permission: $e');
    }
  }

  StreamSubscription<void>? _contactsSubscription;

  void startContactObserver() {
    if (_contactsSubscription != null) return;
    try {
      _contactsSubscription = FlutterContacts.onDatabaseChange.listen((_) {
        debugPrint('[NativeActionService] System contacts database change event received. Re-syncing...');
        syncContacts();
      });
      debugPrint('[NativeActionService] System contacts stream observer registered.');
    } catch (e) {
      debugPrint('[NativeActionService] Failed to register contacts stream observer: $e');
    }
  }

  void dispose() {
    _contactsSubscription?.cancel();
    _contactsSubscription = null;
  }

  Future<void> syncContacts() async {
    try {
      final hasContactsPermission = await Permission.contacts.isGranted;
      if (hasContactsPermission) {
        startContactObserver();
        _cachedContacts = await FlutterContacts.getAll(
          properties: {ContactProperty.name, ContactProperty.phone},
        );
        final names = _cachedContacts.map((c) => (c.displayName ?? '').trim()).toList();
        debugPrint('Loaded ${_cachedContacts.length} contacts from device: $names');
      }
    } catch (e) {
      debugPrint('Error syncing contacts: $e');
    }
  }

  Future<void> syncInstalledApps() async {
    try {
      final List<dynamic>? apps = await _channel.invokeMethod('getInstalledApps');
      if (apps != null) {
        _cachedApps = apps.map((item) {
          final map = item as Map<dynamic, dynamic>;
          return {
            'name': (map['name'] as String? ?? '').trim(),
            'packageName': (map['packageName'] as String? ?? '').trim(),
          };
        }).where((a) => a['name']!.isNotEmpty && a['packageName']!.isNotEmpty).toList();
        debugPrint('Loaded ${_cachedApps.length} installed apps from device.');
      }
    } catch (e) {
      debugPrint('Error syncing installed apps: $e');
    }
  }

  Future<bool> launchApp(String packageName) async {
    try {
      final success = await _channel.invokeMethod<bool>('launchApp', {
        'packageName': packageName,
      });
      return success ?? false;
    } catch (e) {
      debugPrint('Launch app error: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getAppInfo(String target) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('getAppInfo', {
        'name': target,
        'packageName': target,
      });
      return res;
    } catch (e) {
      debugPrint('Get app info error: $e');
      return null;
    }
  }

  List<String> getContactNames() {
    return _cachedContacts
        .map((c) => (c.displayName ?? '').trim())
        .where((name) => name.isNotEmpty)
        .toList();
  }

  Future<bool> setFlashlight(bool enable) async {
    try {
      if (enable) {
        await TorchLight.enableTorch();
        _isTorchOn = true;
      } else {
        await TorchLight.disableTorch();
        _isTorchOn = false;
      }
      return true;
    } catch (e) {
      debugPrint('Torch error: $e');
      return false;
    }
  }

  Future<bool> makeDirectCall(String phoneNumber) async {
    try {
      final cleanNumber = phoneNumber.replaceAll(RegExp(r'[\s\-\(\)]'), '');
      final success = await _channel.invokeMethod<bool>('makeDirectCall', {
        'phoneNumber': cleanNumber,
      });
      return success ?? false;
    } catch (e) {
      debugPrint('Direct call error: $e');
      // Fallback to url_launcher dialer if direct call fails
      final uri = Uri.parse('tel:$phoneNumber');
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri);
      }
      return false;
    }
  }

  Future<bool> callContact(String targetName) async {
    try {
      String? phoneNumber;
      for (final contact in _cachedContacts) {
        final name = (contact.displayName ?? '').toLowerCase();
        if (name.contains(targetName.toLowerCase())) {
          if (contact.phones.isNotEmpty) {
            phoneNumber = contact.phones.first.number;
            break;
          }
        }
      }

      if (phoneNumber != null && phoneNumber.isNotEmpty) {
        return await makeDirectCall(phoneNumber);
      }

      // If no matching contact was found, open the dialer
      return await openDialer();
    } catch (e) {
      debugPrint('Call error: $e');
      return false;
    }
  }

  Future<bool> openDialer() async {
    try {
      final uri = Uri.parse('tel:');
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri);
      }
      return false;
    } catch (e) {
      debugPrint('Open dialer error: $e');
      return false;
    }
  }

  Future<bool> openContactsApp() async {
    try {
      final uri = Uri.parse('content://contacts/people');
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri);
      }
      return false;
    } catch (e) {
      debugPrint('Open contacts error: $e');
      return false;
    }
  }

  Future<bool> openCamera() async {
    try {
      final success = await _channel.invokeMethod<bool>('openCamera');
      return success ?? false;
    } catch (e) {
      debugPrint('Open camera error: $e');
      return false;
    }
  }

  Future<bool> openWifiSettings() async {
    try {
      final success = await _channel.invokeMethod<bool>('openWifiSettings');
      return success ?? false;
    } catch (e) {
      debugPrint('Open Wi-Fi settings error: $e');
      return false;
    }
  }

  Future<bool> openBluetoothSettings() async {
    try {
      final success = await _channel.invokeMethod<bool>('openBluetoothSettings');
      return success ?? false;
    } catch (e) {
      debugPrint('Open Bluetooth settings error: $e');
      return false;
    }
  }

  Future<bool> openSoundSettings() async {
    try {
      final success = await _channel.invokeMethod<bool>('openSoundSettings');
      return success ?? false;
    } catch (e) {
      debugPrint('Open sound settings error: $e');
      return false;
    }
  }

  Future<int> getBatteryLevel() async {
    try {
      final level = await _channel.invokeMethod<int>('getBatteryLevel');
      return level ?? -1;
    } catch (e) {
      debugPrint('Get battery error: $e');
      return -1;
    }
  }

  Future<List<Map<String, dynamic>>> searchFiles({
    String? query,
    String category = 'all',
    int limit = 20,
  }) async {
    try {
      final res = await _channel.invokeListMethod<Map<dynamic, dynamic>>(
        'searchFiles',
        {
          'query': query,
          'category': category,
          'limit': limit,
        },
      );
      if (res == null) return [];
      return res.map((item) => Map<String, dynamic>.from(item)).toList();
    } catch (e) {
      debugPrint('Search files error: $e');
      return [];
    }
  }

  Future<bool> openFile(String filePath) async {
    try {
      final success = await _channel.invokeMethod<bool>('openFile', {'filePath': filePath});
      return success ?? false;
    } catch (e) {
      debugPrint('Open file error: $e');
      return false;
    }
  }

  Future<List<Map<String, String>>> searchContactsNative(String query) async {
    try {
      final res = await _channel.invokeListMethod<Map<dynamic, dynamic>>(
        'searchContacts',
        {'query': query},
      );
      if (res == null) return [];
      return res
          .map((item) => {
                'name': item['name']?.toString() ?? '',
                'number': item['number']?.toString() ?? '',
              })
          .toList();
    } catch (e) {
      debugPrint('Search contacts error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> getStorageDiagnostics() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('getStorageDiagnostics');
      return res ?? {};
    } catch (e) {
      debugPrint('Get storage diagnostics error: $e');
      return {};
    }
  }

  Future<Map<String, dynamic>> toggleFlashlightNative({bool? state}) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('toggleFlashlight', {
        if (state != null) 'state': state,
      });
      return res ?? {'enabled': false, 'message': 'Flashlight state unknown'};
    } catch (e) {
      debugPrint('Toggle flashlight error: $e');
      return {'enabled': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> getMemoryUsage() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('getMemoryUsage');
      return res ?? {};
    } catch (e) {
      debugPrint('Get memory usage error: $e');
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> setVolumeNative({
    String stream = 'media',
    int? level,
    String? direction,
  }) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('setVolume', {
        'stream': stream,
        if (level != null) 'level': level,
        if (direction != null) 'direction': direction,
      });
      return res ?? {};
    } catch (e) {
      debugPrint('Set volume error: $e');
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> getVolumeNative() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('getVolume');
      return res ?? {};
    } catch (e) {
      debugPrint('Get volume error: $e');
      return {'error': e.toString()};
    }
  }

  Future<bool> setClipboardNative(String text) async {
    try {
      final res = await _channel.invokeMethod<bool>('setClipboard', {'text': text});
      return res ?? false;
    } catch (e) {
      debugPrint('Set clipboard error: $e');
      return false;
    }
  }

  Future<String> getClipboardNative() async {
    try {
      final res = await _channel.invokeMethod<String>('getClipboard');
      return res ?? '';
    } catch (e) {
      debugPrint('Get clipboard error: $e');
      return '';
    }
  }

  Future<Map<String, dynamic>> getDeviceInfoNative() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('getDeviceInfo');
      return res ?? {};
    } catch (e) {
      debugPrint('Get device info error: $e');
      return {'error': e.toString()};
    }
  }

  Future<bool> sendSmsNative(String phoneNumber, String message) async {
    try {
      final res = await _channel.invokeMethod<bool>('sendSms', {
        'phoneNumber': phoneNumber,
        'message': message,
      });
      return res ?? false;
    } catch (e) {
      debugPrint('Send SMS error: $e');
      return false;
    }
  }

  Future<bool> openDialerNative(String phoneNumber) async {
    try {
      final res = await _channel.invokeMethod<bool>('openDialer', {
        'phoneNumber': phoneNumber,
      });
      return res ?? false;
    } catch (e) {
      debugPrint('Open dialer error: $e');
      return false;
    }
  }

  Future<List<String>> getRunningAppsNative() async {
    try {
      final res = await _channel.invokeListMethod<dynamic>('getRunningApps');
      return res?.map((e) => e.toString()).toList() ?? [];
    } catch (e) {
      debugPrint('Get running apps error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> mediaControlNative(String action) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('mediaControl', {'action': action});
      return res ?? {'success': true, 'action': action};
    } catch (e) {
      debugPrint('Media control error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> playMediaFromSearchNative(String query, {String packageName = 'com.spotify.music'}) async {
    try {
      final res = await _channel.invokeMethod<bool>('playMediaFromSearch', {
        'query': query,
        'package_name': packageName,
      });
      return {'success': res ?? true, 'query': query, 'package_name': packageName};
    } catch (e) {
      debugPrint('Play media from search error: $e');
      return {'success': false, 'error': e.toString(), 'query': query};
    }
  }

  Future<Map<String, dynamic>> searchYouTubeNative(String query) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('searchYouTube', {
        'query': query,
      });
      return res ?? {'success': true, 'query': query};
    } catch (e) {
      debugPrint('Search YouTube error: $e');
      return {'success': false, 'error': e.toString(), 'query': query};
    }
  }

  Future<bool> showNotificationNative({required String title, required String message}) async {
    try {
      final res = await _channel.invokeMethod<bool>('showNotification', {
        'title': title,
        'message': message,
      });
      return res ?? true;
    } catch (e) {
      debugPrint('Show notification error: $e');
      return false;
    }
  }  Future<Map<String, dynamic>> setAlarmNative({
    required int hour,
    required int minutes,
    String message = 'Alarm',
    bool skipUi = false,
  }) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('setAlarm', {
        'hour': hour,
        'minutes': minutes,
        'message': message,
        'skipUi': skipUi,
      });
      return res ?? {'success': true, 'hour': hour, 'minutes': minutes, 'message': message};
    } catch (e) {
      debugPrint('Set alarm error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> setTimerNative({
    required int lengthSeconds,
    String message = 'Timer',
    bool skipUi = false,
  }) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('setTimer', {
        'lengthSeconds': lengthSeconds,
        'message': message,
        'skipUi': skipUi,
      });
      return res ?? {'success': true, 'lengthSeconds': lengthSeconds, 'message': message};
    } catch (e) {
      debugPrint('Set timer error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<bool> sendKeyEventNative(String key) async {
    try {
      final res = await _channel.invokeMethod<bool>('sendKeyEvent', {'key': key});
      return res ?? false;
    } catch (e) {
      debugPrint('Send key event error: $e');
      return false;
    }
  }

  Future<bool> closeAppNative(String target) async {
    try {
      final res = await _channel.invokeMethod<bool>('closeApp', {'packageName': target});
      return res ?? false;
    } catch (e) {
      debugPrint('Close app error: $e');
      return false;
    }
  }

  Future<String?> readFileNative(String filePath) async {
    try {
      return await _channel.invokeMethod<String>('readFile', {'filePath': filePath});
    } catch (e) {
      debugPrint('Read file error: $e');
      return null;
    }
  }

  Future<bool> writeFileNative(String filePath, String content, {bool append = false}) async {
    try {
      final res = await _channel.invokeMethod<bool>('writeFile', {
        'filePath': filePath,
        'content': content,
        'append': append,
      });
      return res ?? false;
    } catch (e) {
      debugPrint('Write file error: $e');
      return false;
    }
  }

  Future<bool> deleteFileNative(String filePath) async {
    try {
      final res = await _channel.invokeMethod<bool>('deleteFile', {'filePath': filePath});
      return res ?? false;
    } catch (e) {
      debugPrint('Delete file error: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> listStorageLocationsNative() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('listStorageLocations');
      return res ?? {};
    } catch (e) {
      debugPrint('List storage locations error: $e');
      return {};
    }
  }

  Future<bool> openUriNative(String uri) async {
    try {
      final res = await _channel.invokeMethod<bool>('openUri', {'uri': uri});
      return res ?? false;
    } catch (e) {
      debugPrint('Open URI error: $e');
      return false;
    }
  }

  Future<bool> sendIntentNative(String action, {String? uri}) async {
    try {
      final res = await _channel.invokeMethod<bool>('sendIntent', {
        'action': action,
        if (uri != null) 'uri': uri,
      });
      return res ?? false;
    } catch (e) {
      debugPrint('Send intent error: $e');
      return false;
    }
  }

  Future<bool> shareTextNative(String text, {String? subject}) async {
    try {
      final res = await _channel.invokeMethod<bool>('shareText', {
        'text': text,
        if (subject != null) 'subject': subject,
      });
      return res ?? false;
    } catch (e) {
      debugPrint('Share text error: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> getLocationNative() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('getLocation');
      return res ?? {};
    } catch (e) {
      debugPrint('Get location error: $e');
      return {'error': e.toString()};
    }
  }

  Future<bool> tapNative(double x, double y) async {
    try {
      final res = await _channel.invokeMethod<bool>('tap', {'x': x, 'y': y});
      return res ?? false;
    } catch (e) {
      debugPrint('Tap error: $e');
      return false;
    }
  }

  Future<bool> doubleTapNative(double x, double y) async {
    try {
      final res = await _channel.invokeMethod<bool>('doubleTap', {'x': x, 'y': y});
      return res ?? false;
    } catch (e) {
      debugPrint('Double tap error: $e');
      return false;
    }
  }

  Future<bool> longPressNative(double x, double y, {int durationMs = 800}) async {
    try {
      final res = await _channel.invokeMethod<bool>('longPress', {'x': x, 'y': y, 'duration_ms': durationMs});
      return res ?? false;
    } catch (e) {
      debugPrint('Long press error: $e');
      return false;
    }
  }

  Future<bool> swipeNative(double x1, double y1, double x2, double y2, {int durationMs = 300}) async {
    try {
      final res = await _channel.invokeMethod<bool>('swipe', {
        'start_x': x1,
        'start_y': y1,
        'end_x': x2,
        'end_y': y2,
        'duration_ms': durationMs,
      });
      return res ?? false;
    } catch (e) {
      debugPrint('Swipe error: $e');
      return false;
    }
  }

  Future<bool> scrollNative(String direction) async {
    try {
      final res = await _channel.invokeMethod<bool>('scroll', {'direction': direction});
      return res ?? false;
    } catch (e) {
      debugPrint('Scroll error: $e');
      return false;
    }
  }

  Future<bool> typeTextNative(String text) async {
    try {
      final res = await _channel.invokeMethod<bool>('typeText', {'text': text});
      return res ?? false;
    } catch (e) {
      debugPrint('Type text error: $e');
      return false;
    }
  }

  Future<bool> clearTextNative() async {
    try {
      final res = await _channel.invokeMethod<bool>('clearText');
      return res ?? false;
    } catch (e) {
      debugPrint('Clear text error: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getUiTreeNative() async {
    try {
      final res = await _channel.invokeListMethod<dynamic>('getUiTree');
      return res?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
    } catch (e) {
      debugPrint('Get UI tree error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> listNotificationsNative() async {
    try {
      final res = await _channel.invokeListMethod<dynamic>('listNotifications');
      return res?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
    } catch (e) {
      debugPrint('List notifications error: $e');
      return [];
    }
  }

  Future<bool> dismissNotificationNative(String key) async {
    try {
      final res = await _channel.invokeMethod<bool>('dismissNotification', {'key': key});
      return res ?? false;
    } catch (e) {
      debugPrint('Dismiss notification error: $e');
      return false;
    }
  }

  Future<List<String>> listCamerasNative() async {
    try {
      final res = await _channel.invokeListMethod<dynamic>('listCameras');
      return res?.map((e) => e.toString()).toList() ?? [];
    } catch (e) {
      debugPrint('List cameras error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> takeScreenshotNative() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('takeScreenshot');
      return res ?? {'success': true};
    } catch (e) {
      debugPrint('Take screenshot error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }
}

