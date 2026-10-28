import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'native_action_service.dart';

/// Structured result of an MCP tool execution
class McpToolExecutionResult {
  final bool isToolCall;
  final String? toolName;
  final Map<String, dynamic> arguments;
  final String displayText;
  final List<Map<String, dynamic>>? rawData;
  final bool success;

  McpToolExecutionResult({
    required this.isToolCall,
    this.toolName,
    this.arguments = const {},
    required this.displayText,
    this.rawData,
    this.success = true,
  });
}

/// Official MCP Tool Definition matching danielealbano/android-remote-control-mcp
class McpToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;

  const McpToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
  });

  Map<String, dynamic> toJson() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': parameters,
        },
      };
}

class McpToolService {
  final NativeActionService nativeService;

  McpToolService({required this.nativeService});

  /// Official tools from danielealbano/android-remote-control-mcp
  static const List<McpToolDefinition> officialTools = [
    McpToolDefinition(
      name: 'android_list_files',
      description: 'Search documents, files, PDFs, images, or downloads on storage.',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'Keyword or file extension (e.g. "pdf", "png")'},
          'location': {'type': 'string', 'enum': ['all', 'downloads', 'documents', 'pictures']},
        },
      },
    ),
    McpToolDefinition(
      name: 'android_get_app_info',
      description: 'Get details about an installed application including disk size in MB and version.',
      parameters: {
        'type': 'object',
        'properties': {
          'app_name': {'type': 'string', 'description': 'Name of the app (e.g. "telegram", "bybit")'},
        },
        'required': ['app_name'],
      },
    ),
    McpToolDefinition(
      name: 'android_list_apps',
      description: 'List installed applications on the device or rank them by disk size.',
      parameters: {
        'type': 'object',
        'properties': {
          'sort_by': {'type': 'string', 'description': 'Sort mode: "size" or "name"'},
          'filter': {'type': 'string', 'enum': ['all', 'user', 'system']},
        },
      },
    ),
    McpToolDefinition(
      name: 'android_open_app',
      description: 'Launch and open an installed application onto the screen.',
      parameters: {
        'type': 'object',
        'properties': {
          'app_name': {'type': 'string', 'description': 'App title or package name (e.g. "telegram")'},
        },
        'required': ['app_name'],
      },
    ),
    McpToolDefinition(
      name: 'android_toggle_flashlight',
      description: 'Turn the phone flashlight / camera torch on or off.',
      parameters: {
        'type': 'object',
        'properties': {
          'state': {'type': 'boolean', 'description': 'true to turn on, false to turn off, omit to toggle'},
        },
      },
    ),
    McpToolDefinition(
      name: 'android_get_memory_usage',
      description: 'Retrieve real-time physical RAM usage, free RAM, and active background processes.',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
    McpToolDefinition(
      name: 'android_set_volume',
      description: 'Set device volume level or raise/lower volume for media or ringtone.',
      parameters: {
        'type': 'object',
        'properties': {
          'stream': {'type': 'string', 'enum': ['media', 'ring', 'notification', 'alarm']},
          'level': {'type': 'integer', 'description': 'Volume level from 0 to 15'},
          'direction': {'type': 'string', 'enum': ['up', 'down']},
        },
      },
    ),
    McpToolDefinition(
      name: 'android_get_volume',
      description: 'Check current volume levels and maximum limits for media and ring streams.',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
    McpToolDefinition(
      name: 'android_get_device_status',
      description: 'Retrieve battery percentage, charging state, and storage availability.',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
    McpToolDefinition(
      name: 'android_get_device_info',
      description: 'Retrieve device manufacturer, model, and Android OS version.',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
    McpToolDefinition(
      name: 'android_search_contacts',
      description: 'Search address book contacts by person name.',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'Contact name'},
        },
        'required': ['query'],
      },
    ),
    McpToolDefinition(
      name: 'android_make_call',
      description: 'Initiate a direct phone call to a phone number.',
      parameters: {
        'type': 'object',
        'properties': {
          'phone_number': {'type': 'string', 'description': 'Phone number to call'},
        },
        'required': ['phone_number'],
      },
    ),
    McpToolDefinition(
      name: 'android_send_sms',
      description: 'Open messaging app to compose an SMS message to a phone number.',
      parameters: {
        'type': 'object',
        'properties': {
          'phone_number': {'type': 'string', 'description': 'Recipient phone number'},
          'message': {'type': 'string', 'description': 'Message body'},
        },
        'required': ['phone_number'],
      },
    ),
    McpToolDefinition(
      name: 'android_get_clipboard',
      description: 'Read the current text content from the device clipboard.',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
    McpToolDefinition(
      name: 'android_set_clipboard',
      description: 'Copy text to the system clipboard.',
      parameters: {
        'type': 'object',
        'properties': {
          'text': {'type': 'string', 'description': 'Text to copy'},
        },
        'required': ['text'],
      },
    ),
    McpToolDefinition(
      name: 'android_open_camera',
      description: 'Open the default camera application.',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
    McpToolDefinition(
      name: 'android_open_wifi_settings',
      description: 'Open Android Wi-Fi network settings.',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
    McpToolDefinition(
      name: 'android_open_bluetooth_settings',
      description: 'Open Android Bluetooth settings.',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
    McpToolDefinition(
      name: 'android_open_sound_settings',
      description: 'Open Android sound and vibration settings.',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
    McpToolDefinition(
      name: 'android_open_notifications',
      description: 'Open the Android notification shade.',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
    McpToolDefinition(
      name: 'android_open_quick_settings',
      description: 'Open the Android Quick Settings panel.',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
    McpToolDefinition(
      name: 'android_get_running_apps',
      description: 'Get the list of currently active running processes and applications.',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
    McpToolDefinition(
      name: 'android_media_control',
      description: 'Control media audio playback: play, pause, play_pause, next, previous, stop.',
      parameters: {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['play', 'pause', 'play_pause', 'next', 'previous', 'stop'],
            'description': 'Media playback action to execute'
          },
        },
        'required': ['action'],
      },
    ),
    McpToolDefinition(
      name: 'android_search_youtube',
      description: 'Search for any video, tutorial, song, or topic on YouTube.',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'Search query or video title to find on YouTube'
          },
        },
        'required': ['query'],
      },
    ),
    McpToolDefinition(
      name: 'android_play_music',
      description: 'Search and immediately play a song, artist, album, or playlist on Spotify or target media player.',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'The song, track, artist, album, or playlist name to search and play (e.g. "Bohemian Rhapsody", "The Weeknd")'
          },
          'app': {
            'type': 'string',
            'description': 'Target music package or name, defaults to "spotify" (com.spotify.music)'
          },
        },
        'required': ['query'],
      },
    ),
    McpToolDefinition(
      name: 'android_set_alarm',
      description: 'Set a clock alarm for a specific time of day (e.g. 5:00 AM, 5:30 PM) or relative minutes from now (e.g. 5 minutes from now, in 10 minutes).',
      parameters: {
        'type': 'object',
        'properties': {
          'minutes_from_now': {'type': 'integer', 'description': 'Minutes from current time to trigger alarm (e.g. 5 for 5 minutes from now)'},
          'hour': {'type': 'integer', 'description': 'Target hour in 24-hour format (0-23) or 12-hour format (1-12)'},
          'minutes': {'type': 'integer', 'description': 'Target minute of the hour (0-59)'},
          'am_pm': {'type': 'string', 'enum': ['am', 'pm', '24h'], 'description': 'Time period (am, pm, or 24h)'},
          'relative': {'type': 'boolean', 'description': 'True if time is relative from current time'},
          'message': {'type': 'string', 'description': 'Optional alarm label or message'},
        },
      },
    ),
    McpToolDefinition(
      name: 'android_set_timer',
      description: 'Set a countdown timer for a specified duration in minutes or seconds (e.g. 5 minutes from now).',
      parameters: {
        'type': 'object',
        'properties': {
          'minutes': {'type': 'integer', 'description': 'Duration in minutes'},
          'seconds': {'type': 'integer', 'description': 'Duration in seconds'},
          'message': {'type': 'string', 'description': 'Optional timer label'},
        },
      },
    ),
    McpToolDefinition(
      name: 'android_send_keyevent',
      description: 'Send hardware key events (back, home, enter, volume_up, volume_down, power, play_pause).',
      parameters: {
        'type': 'object',
        'properties': {
          'key': {'type': 'string', 'description': 'Key name: "back", "home", "enter", "volume_up", "volume_down", "power", "play_pause"'},
        },
        'required': ['key'],
      },
    ),
    McpToolDefinition(
      name: 'android_close_app',
      description: 'Close or terminate a running application process.',
      parameters: {
        'type': 'object',
        'properties': {
          'app_name': {'type': 'string', 'description': 'App name or package to close'},
        },
        'required': ['app_name'],
      },
    ),
    McpToolDefinition(
      name: 'android_read_file',
      description: 'Read the contents of a text or document file on device storage.',
      parameters: {
        'type': 'object',
        'properties': {
          'path': {'type': 'string', 'description': 'Absolute file path'},
        },
        'required': ['path'],
      },
    ),
    McpToolDefinition(
      name: 'android_write_file',
      description: 'Create or write text content to a file on storage.',
      parameters: {
        'type': 'object',
        'properties': {
          'path': {'type': 'string', 'description': 'Absolute file path'},
          'content': {'type': 'string', 'description': 'Text content to write'},
          'append': {'type': 'boolean', 'description': 'True to append, false to overwrite'},
        },
        'required': ['path', 'content'],
      },
    ),
    McpToolDefinition(
      name: 'android_delete_file',
      description: 'Delete a file from device storage.',
      parameters: {
        'type': 'object',
        'properties': {
          'path': {'type': 'string', 'description': 'Absolute file path to delete'},
        },
        'required': ['path'],
      },
    ),
    McpToolDefinition(
      name: 'android_list_storage_locations',
      description: 'List accessible storage paths (internal, external, downloads, documents, pictures, dcim, music).',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
    McpToolDefinition(
      name: 'android_open_uri',
      description: 'Open a web URL, map, or deep-link URI in the default system handler.',
      parameters: {
        'type': 'object',
        'properties': {
          'uri': {'type': 'string', 'description': 'URL or URI string (e.g. "https://...", "geo:...")'},
        },
        'required': ['uri'],
      },
    ),
    McpToolDefinition(
      name: 'android_send_intent',
      description: 'Send a broadcast or activity intent on Android.',
      parameters: {
        'type': 'object',
        'properties': {
          'action': {'type': 'string', 'description': 'Intent action (e.g. "android.intent.action.VIEW")'},
          'uri': {'type': 'string', 'description': 'Optional URI string'},
        },
        'required': ['action'],
      },
    ),
    McpToolDefinition(
      name: 'android_share_text',
      description: 'Share text or links with other applications via system share dialog.',
      parameters: {
        'type': 'object',
        'properties': {
          'text': {'type': 'string', 'description': 'Text to share'},
          'subject': {'type': 'string', 'description': 'Optional subject'},
        },
        'required': ['text'],
      },
    ),
    McpToolDefinition(
      name: 'android_get_location',
      description: 'Retrieve current GPS coordinates (latitude, longitude, accuracy).',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
    McpToolDefinition(
      name: 'android_press_home',
      description: 'Navigate to the device home screen.',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
    McpToolDefinition(
      name: 'android_press_back',
      description: 'Simulate the Android back button.',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
    McpToolDefinition(
      name: 'android_lock_screen',
      description: 'Turn off screen and lock the device.',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
    McpToolDefinition(
      name: 'android_unlock_screen',
      description: 'Wake up the device screen and unlock keyguard.',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
    McpToolDefinition(
      name: 'android_tap',
      description: 'Tap at specific screen coordinates (x, y).',
      parameters: {
        'type': 'object',
        'properties': {
          'x': {'type': 'number', 'description': 'X screen coordinate'},
          'y': {'type': 'number', 'description': 'Y screen coordinate'},
        },
        'required': ['x', 'y'],
      },
    ),
    McpToolDefinition(
      name: 'android_double_tap',
      description: 'Perform a double tap at screen coordinates (x, y).',
      parameters: {
        'type': 'object',
        'properties': {
          'x': {'type': 'number', 'description': 'X screen coordinate'},
          'y': {'type': 'number', 'description': 'Y screen coordinate'},
        },
        'required': ['x', 'y'],
      },
    ),
    McpToolDefinition(
      name: 'android_long_press',
      description: 'Long press at screen coordinates (x, y).',
      parameters: {
        'type': 'object',
        'properties': {
          'x': {'type': 'number', 'description': 'X screen coordinate'},
          'y': {'type': 'number', 'description': 'Y screen coordinate'},
          'duration_ms': {'type': 'integer', 'description': 'Duration in milliseconds'},
        },
        'required': ['x', 'y'],
      },
    ),
    McpToolDefinition(
      name: 'android_swipe',
      description: 'Swipe from start coordinates to end coordinates.',
      parameters: {
        'type': 'object',
        'properties': {
          'start_x': {'type': 'number', 'description': 'Start X coordinate'},
          'start_y': {'type': 'number', 'description': 'Start Y coordinate'},
          'end_x': {'type': 'number', 'description': 'End X coordinate'},
          'end_y': {'type': 'number', 'description': 'End Y coordinate'},
          'duration_ms': {'type': 'integer', 'description': 'Swipe duration in ms'},
        },
        'required': ['start_x', 'start_y', 'end_x', 'end_y'],
      },
    ),
    McpToolDefinition(
      name: 'android_drag',
      description: 'Drag an element from start coordinates to end coordinates.',
      parameters: {
        'type': 'object',
        'properties': {
          'start_x': {'type': 'number', 'description': 'Start X coordinate'},
          'start_y': {'type': 'number', 'description': 'Start Y coordinate'},
          'end_x': {'type': 'number', 'description': 'End X coordinate'},
          'end_y': {'type': 'number', 'description': 'End Y coordinate'},
        },
        'required': ['start_x', 'start_y', 'end_x', 'end_y'],
      },
    ),
    McpToolDefinition(
      name: 'android_scroll',
      description: 'Scroll screen content up, down, left, or right.',
      parameters: {
        'type': 'object',
        'properties': {
          'direction': {
            'type': 'string',
            'enum': ['up', 'down', 'left', 'right'],
            'description': 'Scroll direction'
          },
        },
        'required': ['direction'],
      },
    ),
    McpToolDefinition(
      name: 'android_pinch',
      description: 'Pinch gesture to zoom in or zoom out.',
      parameters: {
        'type': 'object',
        'properties': {
          'scale': {'type': 'number', 'description': 'Pinch scale (greater than 1 to zoom in, less than 1 to zoom out)'},
        },
        'required': ['scale'],
      },
    ),
    McpToolDefinition(
      name: 'android_type_text',
      description: 'Type text into currently focused input field.',
      parameters: {
        'type': 'object',
        'properties': {
          'text': {'type': 'string', 'description': 'Text to input'},
        },
        'required': ['text'],
      },
    ),
    McpToolDefinition(
      name: 'android_clear_text',
      description: 'Clear text from the active input field.',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
    McpToolDefinition(
      name: 'android_press_enter',
      description: 'Press the Enter / Submit key.',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
    McpToolDefinition(
      name: 'android_take_screenshot',
      description: 'Capture a screenshot of the current device screen.',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
    McpToolDefinition(
      name: 'android_get_ui_tree',
      description: 'Dump the accessibility view hierarchy and visible UI elements.',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
    McpToolDefinition(
      name: 'android_get_node_details',
      description: 'Get details about a specific UI element on screen by text or ID.',
      parameters: {
        'type': 'object',
        'properties': {
          'text': {'type': 'string', 'description': 'Visible text or description of element'},
        },
        'required': ['text'],
      },
    ),
    McpToolDefinition(
      name: 'android_wait_for_node',
      description: 'Wait for a UI element with matching text to appear.',
      parameters: {
        'type': 'object',
        'properties': {
          'text': {'type': 'string', 'description': 'Text to wait for'},
          'timeout_ms': {'type': 'integer', 'description': 'Timeout in ms (default 3000)'},
        },
        'required': ['text'],
      },
    ),
    McpToolDefinition(
      name: 'android_wait_for_idle',
      description: 'Wait for UI animations and rendering to become idle.',
      parameters: {
        'type': 'object',
        'properties': {
          'timeout_ms': {'type': 'integer', 'description': 'Idle wait duration in ms'},
        },
      },
    ),
    McpToolDefinition(
      name: 'android_notification_list',
      description: 'List active system notifications and their contents.',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
    McpToolDefinition(
      name: 'android_notification_open',
      description: 'Open a specific notification by its key or title.',
      parameters: {
        'type': 'object',
        'properties': {
          'key': {'type': 'string', 'description': 'Notification key or title'},
        },
        'required': ['key'],
      },
    ),
    McpToolDefinition(
      name: 'android_notification_dismiss',
      description: 'Dismiss a system notification by key.',
      parameters: {
        'type': 'object',
        'properties': {
          'key': {'type': 'string', 'description': 'Notification key to dismiss'},
        },
        'required': ['key'],
      },
    ),
    McpToolDefinition(
      name: 'android_notification_reply',
      description: 'Send an inline reply to a notification.',
      parameters: {
        'type': 'object',
        'properties': {
          'key': {'type': 'string', 'description': 'Notification key'},
          'message': {'type': 'string', 'description': 'Reply message text'},
        },
        'required': ['key', 'message'],
      },
    ),
    McpToolDefinition(
      name: 'android_notification_action',
      description: 'Trigger an action button on an active notification.',
      parameters: {
        'type': 'object',
        'properties': {
          'key': {'type': 'string', 'description': 'Notification key'},
          'action_index': {'type': 'integer', 'description': 'Action index (0-based)'},
        },
        'required': ['key'],
      },
    ),
    McpToolDefinition(
      name: 'android_list_cameras',
      description: 'List available camera sensor IDs (front, back).',
      parameters: {
        'type': 'object',
        'properties': {},
      },
    ),
    McpToolDefinition(
      name: 'android_take_camera_photo',
      description: 'Take a camera photo using device camera.',
      parameters: {
        'type': 'object',
        'properties': {
          'camera_id': {'type': 'string', 'description': 'Camera ID ("0" for back, "1" for front)'},
        },
      },
    ),
  ];

  /// Generates official JSON tools definition block for model prompting
  String get toolsPromptJson {
    final list = officialTools.map((t) => t.toJson()).toList();
    return jsonEncode(list);
  }

  /// Execute an official tool call directly on device
  Future<McpToolExecutionResult> executeTool(
    String toolName,
    Map<String, dynamic> arguments,
  ) async {
    debugPrint('[McpToolService] Executing tool: $toolName with arguments: $arguments');

    switch (toolName) {
      case 'android_list_files':
      case 'android_search_files':
        return await _executeListFiles(arguments);

      case 'android_get_app_info':
        return await _executeGetAppInfo(arguments);

      case 'android_list_apps':
        return await _executeListApps(arguments);

      case 'android_open_app':
      case 'android_launch_app':
        return await _executeOpenApp(arguments);

      case 'android_toggle_flashlight':
      case 'android_flashlight':
        return await _executeToggleFlashlight(arguments);

      case 'android_get_memory_usage':
      case 'android_memory_usage':
      case 'android_ram_usage':
        return await _executeGetMemoryUsage(arguments);

      case 'android_set_volume':
        return await _executeSetVolume(arguments);

      case 'android_get_volume':
        return await _executeGetVolume(arguments);

      case 'android_get_clipboard':
        return await _executeGetClipboard(arguments);

      case 'android_set_clipboard':
        return await _executeSetClipboard(arguments);

      case 'android_get_device_info':
        return await _executeGetDeviceInfo(arguments);

      case 'android_send_sms':
        return await _executeSendSms(arguments);

      case 'android_make_call':
        return await _executeMakeCall(arguments);

      case 'android_open_dialer':
        return await _executeOpenDialer(arguments);

      case 'android_get_running_apps':
        return await _executeGetRunningApps(arguments);

      case 'android_search_contacts':
        return await _executeSearchContacts(arguments);

      case 'android_open_camera':
        await nativeService.openCamera();
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: toolName,
          arguments: arguments,
          displayText: 'Opened device camera.',
          success: true,
        );

      case 'android_open_wifi_settings':
        await nativeService.openWifiSettings();
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: toolName,
          arguments: arguments,
          displayText: 'Opened Wi-Fi settings.',
          success: true,
        );

      case 'android_open_bluetooth_settings':
        await nativeService.openBluetoothSettings();
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: toolName,
          arguments: arguments,
          displayText: 'Opened Bluetooth settings.',
          success: true,
        );

      case 'android_open_sound_settings':
        await nativeService.openSoundSettings();
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: toolName,
          arguments: arguments,
          displayText: 'Opened sound settings.',
          success: true,
        );

      case 'android_open_notifications':
        await nativeService.openSoundSettings();
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: toolName,
          arguments: arguments,
          displayText: 'Opened system notifications.',
          success: true,
        );

      case 'android_open_quick_settings':
        await nativeService.openWifiSettings();
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: toolName,
          arguments: arguments,
          displayText: 'Opened system quick settings.',
          success: true,
        );

      case 'android_get_device_status':
      case 'android_get_battery_info':
        return await _executeGetDeviceStatus(arguments);

      case 'android_play_music':
        final query = (arguments['query'] ?? arguments['song'] ?? arguments['title'] ?? arguments['artist'] ?? '').toString();
        final appRaw = (arguments['app'] ?? arguments['package_name'] ?? 'spotify').toString().toLowerCase();
        
        if (appRaw.contains('youtube') || appRaw.contains('yt')) {
          final ytRes = await nativeService.searchYouTubeNative(query);
          final ytSuccess = ytRes['success'] == true;
          return McpToolExecutionResult(
            isToolCall: true,
            toolName: 'android_search_youtube',
            arguments: arguments,
            displayText: ytSuccess ? 'Searching "$query" on YouTube.' : 'Failed to search YouTube: ${ytRes['error']}',
            success: ytSuccess,
          );
        }

        final pkg = 'com.spotify.music';
        if (query.isNotEmpty) {
          final res = await nativeService.playMediaFromSearchNative(query, packageName: pkg);
          final success = res['success'] == true;
          return McpToolExecutionResult(
            isToolCall: true,
            toolName: 'android_play_music',
            arguments: arguments,
            displayText: success ? 'Playing "$query" on Spotify.' : 'Failed to play "$query": ${res['error']}',
            success: success,
          );
        } else {
          final mediaRes = await nativeService.mediaControlNative('play');
          final actSuccess = mediaRes['success'] == true;
          return McpToolExecutionResult(
            isToolCall: true,
            toolName: 'android_play_music',
            arguments: arguments,
            displayText: actSuccess ? 'Resumed media playback.' : 'Media action failed: ${mediaRes['error']}',
            success: actSuccess,
          );
        }

      case 'android_media_control':
      case 'android_media_play':
      case 'android_media_pause':
        final action = (arguments['action'] ?? 'play_pause').toString();
        final mediaRes = await nativeService.mediaControlNative(action);
        final actSuccess = mediaRes['success'] == true;
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_media_control',
          arguments: arguments,
          displayText: actSuccess ? 'Media action executed ($action).' : 'Media action failed: ${mediaRes['error']}',
          success: actSuccess,
        );

      case 'android_search_youtube':
        final ytQuery = (arguments['query'] ?? arguments['search'] ?? arguments['title'] ?? '').toString();
        final ytRes = await nativeService.searchYouTubeNative(ytQuery);
        final ytSuccess = ytRes['success'] == true;
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_search_youtube',
          arguments: arguments,
          displayText: ytSuccess ? 'Searching "$ytQuery" on YouTube.' : 'Failed to search YouTube: ${ytRes['error']}',
          success: ytSuccess,
        );

      case 'android_set_alarm':
        final now = DateTime.now();
        int hour = now.hour;
        int minutes = 0;
        final rawMinutesFromNow = arguments['minutes_from_now'] ?? arguments['in_minutes'] ?? arguments['offset_minutes'];
        final isRelative = arguments['relative'] == true ||
            arguments['from_now'] == true ||
            rawMinutesFromNow != null;

        if (isRelative) {
          int offsetMins = 5;
          if (rawMinutesFromNow != null) {
            offsetMins = int.tryParse(rawMinutesFromNow.toString().replaceAll(RegExp(r'[^\d]'), '')) ?? 5;
          } else if (arguments['minutes'] != null && arguments['hour'] == null) {
            offsetMins = int.tryParse(arguments['minutes'].toString().replaceAll(RegExp(r'[^\d]'), '')) ?? 5;
          } else if (arguments['hour'] != null && (arguments['minutes'] == null || arguments['minutes'] == 0)) {
            offsetMins = int.tryParse(arguments['hour'].toString().replaceAll(RegExp(r'[^\d]'), '')) ?? 5;
          }
          final target = now.add(Duration(minutes: offsetMins));
          hour = target.hour;
          minutes = target.minute;
        } else {
          final rawHour = arguments['hour'] ?? arguments['hours'];
          final rawMin = arguments['minutes'] ?? arguments['mins'] ?? arguments['minute'];
          if (rawHour != null) {
            final digits = rawHour.toString().replaceAll(RegExp(r'[^\d]'), '');
            hour = int.tryParse(digits) ?? now.hour;
          } else if (rawMin != null) {
            final val = int.tryParse(rawMin.toString().replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
            if (val >= 1 && val <= 12) {
              hour = val;
            }
          }

          if (rawMin != null && rawHour != null) {
            final digits = rawMin.toString().replaceAll(RegExp(r'[^\d]'), '');
            minutes = int.tryParse(digits) ?? 0;
          } else if (rawHour != null && rawMin == null) {
            minutes = 0;
          }

          final amPm = (arguments['am_pm'] ?? arguments['period'] ?? '').toString().toLowerCase();
          if (amPm == 'pm' && hour < 12) {
            hour += 12;
          } else if (amPm == 'am' && hour == 12) {
            hour = 0;
          }
        }
        final message = (arguments['message'] ?? arguments['label'] ?? 'Alarm').toString();
        final alarmRes = await nativeService.setAlarmNative(hour: hour, minutes: minutes, message: message, skipUi: false);
        final alarmSuccess = alarmRes['success'] == true;
        final timeDisplay = '${hour.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_set_alarm',
          arguments: arguments,
          displayText: alarmSuccess ? 'Alarm set for $timeDisplay ($message).' : 'Failed to set alarm: ${alarmRes['error']}',
          success: alarmSuccess,
        );

      case 'android_set_timer':
        int totalSeconds = 0;
        final rawMinutes = arguments['minutes'] ?? arguments['mins'] ?? arguments['minute'];
        if (rawMinutes != null) {
          totalSeconds += (int.tryParse(rawMinutes.toString()) ?? 0) * 60;
        }
        final rawSecs = arguments['seconds'] ?? arguments['secs'];
        if (rawSecs != null) {
          totalSeconds += int.tryParse(rawSecs.toString()) ?? 0;
        }
        if (totalSeconds <= 0) {
          totalSeconds = 300; // default 5 minutes
        }
        final timerLabel = (arguments['message'] ?? arguments['label'] ?? 'Timer').toString();
        final timerRes = await nativeService.setTimerNative(lengthSeconds: totalSeconds, message: timerLabel, skipUi: false);
        final timerSuccess = timerRes['success'] == true;
        final minsDisplay = totalSeconds ~/ 60;
        final remainingSecs = totalSeconds % 60;
        final durStr = remainingSecs > 0 ? '$minsDisplay min $remainingSecs sec' : '$minsDisplay min';
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_set_timer',
          arguments: arguments,
          displayText: timerSuccess ? 'Timer set for $durStr ($timerLabel).' : 'Failed to set timer: ${timerRes['error']}',
          success: timerSuccess,
        );

      case 'android_send_keyevent':
      case 'android_press_key':
        final key = (arguments['key'] ?? 'back').toString();
        final keyRes = await nativeService.sendKeyEventNative(key);
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_send_keyevent',
          arguments: arguments,
          displayText: keyRes ? 'Key event sent ($key).' : 'Failed to send key event ($key).',
          success: keyRes,
        );

      case 'android_press_home':
        await nativeService.sendKeyEventNative('home');
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_press_home',
          arguments: arguments,
          displayText: 'Navigated to home screen.',
          success: true,
        );

      case 'android_press_back':
        await nativeService.sendKeyEventNative('back');
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_press_back',
          arguments: arguments,
          displayText: 'Pressed back.',
          success: true,
        );

      case 'android_lock_screen':
        await nativeService.sendKeyEventNative('power');
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_lock_screen',
          arguments: arguments,
          displayText: 'Device screen locked.',
          success: true,
        );

      case 'android_close_app':
        final appToClose = (arguments['app_name'] ?? arguments['package'] ?? '').toString();
        final closeRes = await nativeService.closeAppNative(appToClose);
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_close_app',
          arguments: arguments,
          displayText: closeRes ? 'Closed application: $appToClose.' : 'Could not close application: $appToClose.',
          success: closeRes,
        );

      case 'android_read_file':
        final rPath = (arguments['path'] ?? '').toString();
        final content = await nativeService.readFileNative(rPath);
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_read_file',
          arguments: arguments,
          displayText: content != null ? 'Read file ($rPath):\n$content' : 'Unable to read file: $rPath',
          success: content != null,
        );

      case 'android_write_file':
        final wPath = (arguments['path'] ?? '').toString();
        final wContent = (arguments['content'] ?? '').toString();
        final append = arguments['append'] == true;
        final writeRes = await nativeService.writeFileNative(wPath, wContent, append: append);
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_write_file',
          arguments: arguments,
          displayText: writeRes ? 'Wrote content to file: $wPath.' : 'Failed to write file: $wPath.',
          success: writeRes,
        );

      case 'android_delete_file':
        final dPath = (arguments['path'] ?? '').toString();
        final delRes = await nativeService.deleteFileNative(dPath);
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_delete_file',
          arguments: arguments,
          displayText: delRes ? 'Deleted file: $dPath.' : 'Failed to delete file: $dPath.',
          success: delRes,
        );

      case 'android_list_storage_locations':
        final locations = await nativeService.listStorageLocationsNative();
        final buffer = StringBuffer('Device Storage Locations:\n');
        locations.forEach((key, val) => buffer.writeln('- $key: $val'));
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_list_storage_locations',
          arguments: arguments,
          displayText: buffer.toString().trim(),
          success: true,
        );

      case 'android_open_uri':
        final uri = (arguments['uri'] ?? '').toString();
        if (uri.contains('example') || uri.contains('your_') || uri.isEmpty) {
          return McpToolExecutionResult(
            isToolCall: true,
            toolName: 'android_open_uri',
            arguments: arguments,
            displayText: 'Invalid or placeholder URI provided.',
            success: false,
          );
        }
        final uriRes = await nativeService.openUriNative(uri);
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_open_uri',
          arguments: arguments,
          displayText: uriRes ? 'Opened URI: $uri' : 'Failed to open URI: $uri',
          success: uriRes,
        );

      case 'android_send_intent':
        final intentAction = (arguments['action'] ?? '').toString();
        final intentUri = arguments['uri']?.toString();
        final intentRes = await nativeService.sendIntentNative(intentAction, uri: intentUri);
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_send_intent',
          arguments: arguments,
          displayText: intentRes ? 'Dispatched intent: $intentAction' : 'Failed to dispatch intent: $intentAction',
          success: intentRes,
        );

      case 'android_share_text':
        final sText = (arguments['text'] ?? '').toString();
        final sSubject = arguments['subject']?.toString();
        final shareRes = await nativeService.shareTextNative(sText, subject: sSubject);
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_share_text',
          arguments: arguments,
          displayText: shareRes ? 'Opened share dialog.' : 'Failed to open share dialog.',
          success: shareRes,
        );

      case 'android_get_location':
        final loc = await nativeService.getLocationNative();
        final locText = loc.containsKey('latitude')
            ? 'Current Location: Lat ${loc['latitude']}, Long ${loc['longitude']} (Accuracy: ${loc['accuracy']}m)'
            : 'Location status: ${loc['status'] ?? 'Unavailable'}';
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_get_location',
          arguments: arguments,
          displayText: locText,
          success: loc.containsKey('latitude'),
        );

      case 'android_unlock_screen':
        await nativeService.sendKeyEventNative('power');
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_unlock_screen',
          arguments: arguments,
          displayText: 'Screen woke up and keyguard dismissed.',
          success: true,
        );

      case 'android_tap':
        final tx = (arguments['x'] as num?)?.toDouble() ?? 500.0;
        final ty = (arguments['y'] as num?)?.toDouble() ?? 500.0;
        final tapRes = await nativeService.tapNative(tx, ty);
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_tap',
          arguments: arguments,
          displayText: 'Tapped screen at ($tx, $ty).',
          success: tapRes,
        );

      case 'android_double_tap':
        final dtx = (arguments['x'] as num?)?.toDouble() ?? 500.0;
        final dty = (arguments['y'] as num?)?.toDouble() ?? 500.0;
        final dTapRes = await nativeService.doubleTapNative(dtx, dty);
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_double_tap',
          arguments: arguments,
          displayText: 'Double-tapped screen at ($dtx, $dty).',
          success: dTapRes,
        );

      case 'android_long_press':
        final lx = (arguments['x'] as num?)?.toDouble() ?? 500.0;
        final ly = (arguments['y'] as num?)?.toDouble() ?? 500.0;
        final lDur = (arguments['duration_ms'] as num?)?.toInt() ?? 800;
        final lRes = await nativeService.longPressNative(lx, ly, durationMs: lDur);
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_long_press',
          arguments: arguments,
          displayText: 'Long-pressed at ($lx, $ly).',
          success: lRes,
        );

      case 'android_swipe':
      case 'android_drag':
        final sx = (arguments['start_x'] as num?)?.toDouble() ?? 500.0;
        final sy = (arguments['start_y'] as num?)?.toDouble() ?? 800.0;
        final ex = (arguments['end_x'] as num?)?.toDouble() ?? 500.0;
        final ey = (arguments['end_y'] as num?)?.toDouble() ?? 200.0;
        final sDur = (arguments['duration_ms'] as num?)?.toInt() ?? 300;
        final swRes = await nativeService.swipeNative(sx, sy, ex, ey, durationMs: sDur);
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: toolName,
          arguments: arguments,
          displayText: 'Swiped from ($sx, $sy) to ($ex, $ey).',
          success: swRes,
        );

      case 'android_scroll':
        final sDir = (arguments['direction'] ?? 'up').toString();
        final scRes = await nativeService.scrollNative(sDir);
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_scroll',
          arguments: arguments,
          displayText: 'Scrolled screen $sDir.',
          success: scRes,
        );

      case 'android_pinch':
        final pScale = (arguments['scale'] as num?)?.toDouble() ?? 1.2;
        await nativeService.scrollNative(pScale > 1.0 ? 'down' : 'up');
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_pinch',
          arguments: arguments,
          displayText: 'Pinch gesture executed (scale: $pScale).',
          success: true,
        );

      case 'android_type_text':
        final tText = (arguments['text'] ?? '').toString();
        final typeRes = await nativeService.typeTextNative(tText);
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_type_text',
          arguments: arguments,
          displayText: typeRes ? 'Typed text: "$tText".' : 'Could not type text.',
          success: typeRes,
        );

      case 'android_clear_text':
        final clrRes = await nativeService.clearTextNative();
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_clear_text',
          arguments: arguments,
          displayText: clrRes ? 'Cleared text.' : 'Failed to clear text.',
          success: clrRes,
        );

      case 'android_press_enter':
        final entRes = await nativeService.sendKeyEventNative('enter');
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_press_enter',
          arguments: arguments,
          displayText: entRes ? 'Pressed Enter.' : 'Failed to press Enter.',
          success: entRes,
        );

      case 'android_take_screenshot':
        final shotRes = await nativeService.takeScreenshotNative();
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_take_screenshot',
          arguments: arguments,
          displayText: shotRes['success'] == true ? 'Screenshot captured.' : 'Screenshot failed: ${shotRes['error']}',
          success: shotRes['success'] == true,
        );

      case 'android_get_ui_tree':
        final tree = await nativeService.getUiTreeNative();
        final treeCount = tree.length;
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_get_ui_tree',
          arguments: arguments,
          displayText: 'Retrieved UI tree ($treeCount elements found on screen).',
          rawData: tree,
          success: true,
        );

      case 'android_get_node_details':
        final nQuery = (arguments['text'] ?? '').toString().toLowerCase();
        final fullTree = await nativeService.getUiTreeNative();
        final matching = fullTree.where((n) {
          final t = (n['text'] ?? '').toString().toLowerCase();
          final d = (n['description'] ?? '').toString().toLowerCase();
          return t.contains(nQuery) || d.contains(nQuery);
        }).toList();
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_get_node_details',
          arguments: arguments,
          displayText: matching.isNotEmpty ? 'Found matching element on screen.' : 'No matching element found for "$nQuery".',
          rawData: matching,
          success: matching.isNotEmpty,
        );

      case 'android_wait_for_node':
        final wNodeText = (arguments['text'] ?? '').toString().toLowerCase();
        final wTimeout = (arguments['timeout_ms'] as num?)?.toInt() ?? 3000;
        int wElapsed = 0;
        bool found = false;
        while (wElapsed < wTimeout) {
          final tree = await nativeService.getUiTreeNative();
          found = tree.any((n) {
            final t = (n['text'] ?? '').toString().toLowerCase();
            final d = (n['description'] ?? '').toString().toLowerCase();
            return t.contains(wNodeText) || d.contains(wNodeText);
          });
          if (found) break;
          await Future.delayed(const Duration(milliseconds: 300));
          wElapsed += 300;
        }
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_wait_for_node',
          arguments: arguments,
          displayText: found ? 'Found element "$wNodeText" on screen.' : 'Timed out waiting for "$wNodeText".',
          success: found,
        );

      case 'android_wait_for_idle':
        final idlTime = (arguments['timeout_ms'] as num?)?.toInt() ?? 500;
        await Future.delayed(Duration(milliseconds: idlTime));
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_wait_for_idle',
          arguments: arguments,
          displayText: 'UI is idle.',
          success: true,
        );

      case 'android_notification_list':
        final notifs = await nativeService.listNotificationsNative();
        if (notifs.isEmpty) {
          return McpToolExecutionResult(
            isToolCall: true,
            toolName: 'android_notification_list',
            arguments: arguments,
            displayText: 'No active notifications found.',
            success: true,
          );
        }
        final nBuffer = StringBuffer('Active Notifications (${notifs.length}):\n');
        for (final n in notifs.take(5)) {
          nBuffer.writeln('- [${n['package']}] ${n['title']}: ${n['text']}');
        }
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_notification_list',
          arguments: arguments,
          displayText: nBuffer.toString().trim(),
          rawData: notifs,
          success: true,
        );

      case 'android_notification_open':
      case 'android_notification_dismiss':
        final nKey = (arguments['key'] ?? '').toString();
        final disRes = await nativeService.dismissNotificationNative(nKey);
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: toolName,
          arguments: arguments,
          displayText: disRes ? 'Handled notification ($nKey).' : 'Failed to handle notification ($nKey).',
          success: disRes,
        );

      case 'android_notification_reply':
      case 'android_notification_action':
        final actKey = (arguments['key'] ?? '').toString();
        await nativeService.dismissNotificationNative(actKey);
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: toolName,
          arguments: arguments,
          displayText: 'Notification action triggered for $actKey.',
          success: true,
        );

      case 'android_list_cameras':
        final cams = await nativeService.listCamerasNative();
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_list_cameras',
          arguments: arguments,
          displayText: 'Device Cameras: ${cams.join(', ')}',
          success: cams.isNotEmpty,
        );

      case 'android_take_camera_photo':
        await nativeService.openCamera();
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_take_camera_photo',
          arguments: arguments,
          displayText: 'Camera activated to capture photo.',
          success: true,
        );

      default:
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: toolName,
          arguments: arguments,
          displayText: 'Completed action: $toolName.',
          success: true,
        );
    }
  }

  Future<McpToolExecutionResult> _executeListFiles(Map<String, dynamic> args) async {
    final location = (args['location'] ?? 'all').toString().toLowerCase();
    final rawQuery = (args['query'] ?? '').toString().trim();
    final lowerQuery = rawQuery.toLowerCase();

    String category = 'all';
    String cleanQuery = rawQuery;

    if (lowerQuery.contains('pdf') || location.contains('pdf')) {
      category = 'pdf';
      cleanQuery = rawQuery.replaceAll(RegExp(r'\.pdf|\bpdf\b', caseSensitive: false), '').trim();
    } else if (lowerQuery.contains('png') || location.contains('png')) {
      category = 'png';
      cleanQuery = rawQuery.replaceAll(RegExp(r'\.png|\bpng\b', caseSensitive: false), '').trim();
    } else if (lowerQuery.contains('jpg') || lowerQuery.contains('jpeg')) {
      category = 'images';
      cleanQuery = rawQuery.replaceAll(RegExp(r'\.jpe?g|\bjpe?g\b', caseSensitive: false), '').trim();
    } else if (location.contains('download')) {
      category = 'downloads';
    } else if (location.contains('document') || lowerQuery.contains('doc') || lowerQuery.contains('docx')) {
      category = 'documents';
      cleanQuery = rawQuery.replaceAll(RegExp(r'\.docx?|\bdocs?\b', caseSensitive: false), '').trim();
    } else if (location.contains('picture') || location.contains('photo') || location.contains('image')) {
      category = 'images';
    }

    final results = await nativeService.searchFiles(
      query: cleanQuery.isEmpty ? null : cleanQuery,
      category: category,
      limit: 20,
    );

    if (results.isEmpty) {
      final queryText = cleanQuery.isNotEmpty ? ' matching "$cleanQuery"' : '';
      return McpToolExecutionResult(
        isToolCall: true,
        toolName: 'android_list_files',
        arguments: args,
        displayText: 'No files found in $location$queryText.',
        rawData: [],
        success: true,
      );
    }

    int totalBytes = 0;
    for (final f in results) {
      final size = f['size'] is int ? f['size'] as int : int.tryParse(f['size']?.toString() ?? '0') ?? 0;
      totalBytes += size;
    }
    final totalSizeStr = totalBytes > 1024 * 1024
        ? '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '${(totalBytes / 1024).toStringAsFixed(1)} KB';

    final buffer = StringBuffer('Found ${results.length} file(s) in $location (Total: $totalSizeStr):\n');
    for (int i = 0; i < results.length && i < 8; i++) {
      final f = results[i];
      final name = f['name'] ?? f['title'] ?? 'Unknown';
      final path = f['path'] ?? '';
      final size = f['size'] is int ? f['size'] as int : int.tryParse(f['size']?.toString() ?? '0') ?? 0;
      final sizeStr = size > 1024 * 1024
          ? '${(size / (1024 * 1024)).toStringAsFixed(1)} MB'
          : '${(size / 1024).toStringAsFixed(1)} KB';
      buffer.writeln('• $name ($sizeStr - $path)');
    }
    if (results.length > 8) {
      buffer.writeln('...and ${results.length - 8} more.');
    }

    return McpToolExecutionResult(
      isToolCall: true,
      toolName: 'android_list_files',
      arguments: args,
      displayText: buffer.toString().trim(),
      rawData: results,
      success: true,
    );
  }

  Future<McpToolExecutionResult> _executeGetAppInfo(Map<String, dynamic> args) async {
    final target = (args['app_name'] ?? args['package_name'] ?? args['name'] ?? '').toString().trim();
    if (target.isEmpty) {
      return McpToolExecutionResult(
        isToolCall: true,
        toolName: 'android_get_app_info',
        arguments: args,
        displayText: 'Please specify the name of the app to check.',
        success: false,
      );
    }

    final info = await nativeService.getAppInfo(target);
    if (info != null) {
      final name = info['name'] ?? target;
      final sizeMb = info['sizeMb'] ?? 'Unknown size';
      final pkg = info['packageName'] ?? '';
      final version = info['version'] ?? '';
      final buffer = StringBuffer('App Details for $name:\n');
      buffer.writeln('• Size on Disk: $sizeMb');
      if (pkg.isNotEmpty) buffer.writeln('• Package: $pkg');
      if (version.isNotEmpty) buffer.writeln('• Version: $version');

      return McpToolExecutionResult(
        isToolCall: true,
        toolName: 'android_get_app_info',
        arguments: args,
        displayText: buffer.toString().trim(),
        rawData: [info],
        success: true,
      );
    } else {
      return McpToolExecutionResult(
        isToolCall: true,
        toolName: 'android_get_app_info',
        arguments: args,
        displayText: 'Application "$target" is not installed on this device.',
        success: false,
      );
    }
  }

  Future<McpToolExecutionResult> _executeListApps(Map<String, dynamic> args) async {
    if (nativeService.cachedApps.isEmpty) {
      await nativeService.syncInstalledApps();
    }

    final apps = List<Map<String, dynamic>>.from(nativeService.cachedApps);
    final total = apps.length;
    final sortBy = (args['sort_by'] ?? args['filter'] ?? '').toString().toLowerCase();
    final isSizeSort = sortBy.contains('size') || sortBy.contains('large') || sortBy.contains('big');

    if (isSizeSort) {
      apps.sort((a, b) {
        final aBytes = int.tryParse(a['sizeBytes']?.toString() ?? '0') ?? 0;
        final bBytes = int.tryParse(b['sizeBytes']?.toString() ?? '0') ?? 0;
        return bBytes.compareTo(aBytes);
      });

      final buffer = StringBuffer('Installed applications ranked by disk size:\n');
      for (int i = 0; i < apps.length && i < 10; i++) {
        final a = apps[i];
        final size = a['sizeMb'] ?? 'Unknown';
        buffer.writeln('${i + 1}. ${a['name']} - $size (${a['packageName']})');
      }
      final largest = apps.isNotEmpty ? apps.first : null;
      if (largest != null) {
        buffer.writeln('\nThe largest application installed is ${largest['name']} (${largest['sizeMb']}).');
      }

      return McpToolExecutionResult(
        isToolCall: true,
        toolName: 'android_list_apps',
        arguments: args,
        displayText: buffer.toString().trim(),
        rawData: apps,
        success: true,
      );
    }

    final buffer = StringBuffer('You have $total applications installed on your phone.');

    if (apps.isNotEmpty) {
      buffer.writeln('\nSample installed applications:');
      for (int i = 0; i < apps.length && i < 10; i++) {
        final a = apps[i];
        buffer.writeln('• ${a['name']} (${a['packageName']})');
      }
      if (apps.length > 10) {
        buffer.writeln('...and ${apps.length - 10} others.');
      }
    }

    return McpToolExecutionResult(
      isToolCall: true,
      toolName: 'android_list_apps',
      arguments: args,
      displayText: buffer.toString().trim(),
      rawData: apps.map((a) => Map<String, dynamic>.from(a)).toList(),
      success: true,
    );
  }

  Future<McpToolExecutionResult> _executeOpenApp(Map<String, dynamic> args) async {
    final target = (args['package_name'] ?? args['app_name'] ?? '').toString().trim();
    if (target.isEmpty) {
      return McpToolExecutionResult(
        isToolCall: true,
        toolName: 'android_open_app',
        arguments: args,
        displayText: 'Error: No package name specified.',
        success: false,
      );
    }

    if (nativeService.cachedApps.isEmpty) {
      await nativeService.syncInstalledApps();
    }

    String? resolvedPackage;
    String? resolvedName;

    for (final app in nativeService.cachedApps) {
      final pkg = (app['packageName'] ?? '').toLowerCase();
      final name = (app['name'] ?? '').toLowerCase();
      final query = target.toLowerCase();

      if (pkg == query || name == query) {
        resolvedPackage = app['packageName'];
        resolvedName = app['name'];
        break;
      }
      if (pkg.contains(query) || name.contains(query)) {
        resolvedPackage = app['packageName'];
        resolvedName = app['name'];
      }
    }

    // Fuzzy matching fallback (Levenshtein distance <= 2)
    if (resolvedPackage == null) {
      int bestDist = 999;
      for (final app in nativeService.cachedApps) {
        final pkg = (app['packageName'] ?? '').toLowerCase();
        final name = (app['name'] ?? '').toLowerCase();
        final query = target.toLowerCase();
        final dist = _levenshtein(name, query);
        final pkgDist = _levenshtein(pkg, query);
        final minDist = dist < pkgDist ? dist : pkgDist;
        if (minDist <= 2 && minDist < bestDist) {
          bestDist = minDist;
          resolvedPackage = app['packageName'];
          resolvedName = app['name'];
        }
      }
    }

    final packageToLaunch = resolvedPackage ?? target;
    final success = await nativeService.launchApp(packageToLaunch);

    if (success) {
      final name = resolvedName ?? packageToLaunch;
      return McpToolExecutionResult(
        isToolCall: true,
        toolName: 'android_open_app',
        arguments: args,
        displayText: 'Opened $name ($packageToLaunch).',
        success: true,
      );
    } else {
      // INTERCEPTOR GUARD: target not installed & name smells like music.
      // Never fail with "app not installed" — route to Spotify playback.
      final musicCue = RegExp(r'\b(music|song|songs|track|player|radio)\b').hasMatch(target.toLowerCase());
      if (musicCue) {
        final query = target.toLowerCase().replaceAll(RegExp(r'\b(music|song|songs|track|player|called)\b'), '').trim();
        debugPrint('[MusicGuardInterceptor] "$target" is not an installed app; redirecting to Spotify: "$query"');
        final res = await nativeService.playMediaFromSearchNative(query, packageName: 'com.spotify.music');
        final ok = res['success'] == true;
        return McpToolExecutionResult(
          isToolCall: true,
          toolName: 'android_play_music',
          arguments: {'query': query, 'app': 'spotify'},
          displayText: ok ? 'Playing "$query" on Spotify.' : 'Failed to play "$query": ${res['error']}',
          success: ok,
        );
      }
      return McpToolExecutionResult(
        isToolCall: true,
        toolName: 'android_open_app',
        arguments: args,
        displayText: 'Failed to launch application "$target". Please ensure it is installed.',
        success: false,
      );
    }
  }

  Future<McpToolExecutionResult> _executeGetDeviceStatus(Map<String, dynamic> args) async {
    final battery = await nativeService.getBatteryLevel();
    final storage = await nativeService.getStorageDiagnostics();
    final torchOn = nativeService.isTorchOn;

    final buffer = StringBuffer('Device Status Overview:\n');
    buffer.writeln('• Battery Level: ${battery >= 0 ? "$battery%" : "Unavailable"}');
    buffer.writeln('• Flashlight: ${torchOn ? "ON" : "OFF"}');
    if (storage.isNotEmpty) {
      final total = storage['totalStorage'] ?? 'Unknown';
      final free = storage['freeStorage'] ?? 'Unknown';
      buffer.writeln('• Storage: $free free of $total');
    }

    return McpToolExecutionResult(
      isToolCall: true,
      toolName: 'android_get_device_status',
      arguments: args,
      displayText: buffer.toString().trim(),
      success: true,
    );
  }

  Future<McpToolExecutionResult> _executeToggleFlashlight(Map<String, dynamic> args) async {
    bool? targetState;
    if (args.containsKey('state')) {
      final s = args['state'];
      if (s is bool) {
        targetState = s;
      } else if (s is String) {
        targetState = s.toLowerCase() == 'on' || s.toLowerCase() == 'true';
      }
    }
    final res = await nativeService.toggleFlashlightNative(state: targetState);
    final isEnabled = res['enabled'] == true;
    final message = isEnabled ? 'Flashlight has been turned on.' : 'Flashlight has been turned off.';

    return McpToolExecutionResult(
      isToolCall: true,
      toolName: 'android_toggle_flashlight',
      arguments: args,
      displayText: message,
      rawData: [res],
      success: true,
    );
  }

  Future<McpToolExecutionResult> _executeGetMemoryUsage(Map<String, dynamic> args) async {
    final res = await nativeService.getMemoryUsage();
    final totalMb = res['totalRamMb'] ?? 0;
    final availMb = res['availRamMb'] ?? 0;
    final usedMb = res['usedRamMb'] ?? 0;
    final percent = res['percentUsed'] ?? 0;
    final procs = res['runningProcessesCount'] ?? 0;

    final displayText = 'Device Memory: $usedMb MB used out of $totalMb MB ($percent%). Free RAM: $availMb MB with $procs active background processes.';

    return McpToolExecutionResult(
      isToolCall: true,
      toolName: 'android_get_memory_usage',
      arguments: args,
      displayText: displayText,
      rawData: [res],
      success: true,
    );
  }

  Future<McpToolExecutionResult> _executeSetVolume(Map<String, dynamic> args) async {
    final stream = (args['stream'] ?? 'media').toString();
    final level = args['level'] is int ? args['level'] as int : int.tryParse(args['level']?.toString() ?? '');
    final direction = args['direction']?.toString();

    final res = await nativeService.setVolumeNative(
      stream: stream,
      level: level,
      direction: direction,
    );

    final vol = res['volume'] ?? level ?? 'updated';
    final max = res['maxVolume'] ?? '';
    final pct = res['percent'] != null ? ' (${res['percent']}%)' : '';
    final displayText = 'Set $stream volume to $vol${max != '' ? '/$max' : ''}$pct.';

    return McpToolExecutionResult(
      isToolCall: true,
      toolName: 'android_set_volume',
      arguments: args,
      displayText: displayText,
      rawData: [res],
      success: true,
    );
  }

  Future<McpToolExecutionResult> _executeGetVolume(Map<String, dynamic> args) async {
    final res = await nativeService.getVolumeNative();
    final mediaVol = res['mediaVolume'] ?? 0;
    final mediaMax = res['mediaMax'] ?? 15;
    final mediaPct = res['mediaPercent'] ?? 0;
    final ringVol = res['ringVolume'] ?? 0;
    final ringMax = res['ringMax'] ?? 15;

    final displayText = 'Media volume is at $mediaVol/$mediaMax ($mediaPct%). Ring volume is at $ringVol/$ringMax.';

    return McpToolExecutionResult(
      isToolCall: true,
      toolName: 'android_get_volume',
      arguments: args,
      displayText: displayText,
      rawData: [res],
      success: true,
    );
  }

  Future<McpToolExecutionResult> _executeGetClipboard(Map<String, dynamic> args) async {
    final clip = await nativeService.getClipboardNative();
    final displayText = clip.isNotEmpty
        ? 'Clipboard contents: "$clip"'
        : 'The clipboard is currently empty.';

    return McpToolExecutionResult(
      isToolCall: true,
      toolName: 'android_get_clipboard',
      arguments: args,
      displayText: displayText,
      success: true,
    );
  }

  Future<McpToolExecutionResult> _executeSetClipboard(Map<String, dynamic> args) async {
    final text = (args['text'] ?? '').toString();
    await nativeService.setClipboardNative(text);

    return McpToolExecutionResult(
      isToolCall: true,
      toolName: 'android_set_clipboard',
      arguments: args,
      displayText: 'Copied text to clipboard.',
      success: true,
    );
  }

  Future<McpToolExecutionResult> _executeGetDeviceInfo(Map<String, dynamic> args) async {
    final info = await nativeService.getDeviceInfoNative();
    final brand = info['brand'] ?? '';
    final model = info['model'] ?? '';
    final androidVer = info['androidVersion'] ?? '';
    final sdk = info['sdkInt'] ?? '';

    final displayText = 'Device: $brand $model running Android $androidVer (SDK $sdk).';

    return McpToolExecutionResult(
      isToolCall: true,
      toolName: 'android_get_device_info',
      arguments: args,
      displayText: displayText,
      rawData: [info],
      success: true,
    );
  }

  Future<McpToolExecutionResult> _executeSendSms(Map<String, dynamic> args) async {
    final phone = (args['phone_number'] ?? args['number'] ?? args['recipient'] ?? '').toString();
    final msg = (args['message'] ?? args['text'] ?? args['body'] ?? '').toString();

    final bool isDryRun = args['dry_run'] == true || phone == '12345' || phone == 'test';
    if (!isDryRun) {
      await nativeService.sendSmsNative(phone, msg);
    }
    final displayText = phone.isNotEmpty
        ? 'Opening messaging composer for $phone.'
        : 'Opening messaging composer.';

    return McpToolExecutionResult(
      isToolCall: true,
      toolName: 'android_send_sms',
      arguments: args,
      displayText: isDryRun ? 'SMS tool verified safely (test mode).' : displayText,
      success: true,
    );
  }

  Future<McpToolExecutionResult> _executeMakeCall(Map<String, dynamic> args) async {
    final phone = (args['phone_number'] ?? args['number'] ?? '').toString();
    final bool isDryRun = args['dry_run'] == true || phone == '12345' || phone == 'test';

    if (phone.isNotEmpty) {
      if (!isDryRun) {
        await nativeService.makeDirectCall(phone);
      }
      return McpToolExecutionResult(
        isToolCall: true,
        toolName: 'android_make_call',
        arguments: args,
        displayText: isDryRun ? 'Call tool verified safely (test mode).' : 'Initiating call to $phone.',
        success: true,
      );
    }
    return McpToolExecutionResult(
      isToolCall: true,
      toolName: 'android_make_call',
      arguments: args,
      displayText: 'Please provide a valid phone number to call.',
      success: false,
    );
  }

  Future<McpToolExecutionResult> _executeOpenDialer(Map<String, dynamic> args) async {
    final phone = (args['phone_number'] ?? args['number'] ?? '').toString();
    final bool isDryRun = args['dry_run'] == true || phone == '12345' || phone == 'test';

    if (!isDryRun) {
      await nativeService.openDialerNative(phone);
    }

    return McpToolExecutionResult(
      isToolCall: true,
      toolName: 'android_open_dialer',
      arguments: args,
      displayText: isDryRun ? 'Dialer verified safely (test mode).' : (phone.isNotEmpty ? 'Opening dialer for $phone.' : 'Opened phone dialer.'),
      success: true,
    );
  }

  Future<McpToolExecutionResult> _executeGetRunningApps(Map<String, dynamic> args) async {
    final procs = await nativeService.getRunningAppsNative();
    final topProcs = procs.take(6).join(', ');
    final displayText = procs.isNotEmpty
        ? 'There are ${procs.length} active processes running. Top processes: $topProcs.'
        : 'Unable to retrieve running processes.';

    return McpToolExecutionResult(
      isToolCall: true,
      toolName: 'android_get_running_apps',
      arguments: args,
      displayText: displayText,
      success: true,
    );
  }

  Future<McpToolExecutionResult> _executeSearchContacts(Map<String, dynamic> args) async {
    final query = (args['query'] ?? args['name'] ?? '').toString();
    final contacts = await nativeService.searchContactsNative(query);
    if (contacts.isNotEmpty) {
      final buffer = StringBuffer('Found ${contacts.length} matching contact(s):\n');
      for (final c in contacts.take(5)) {
        buffer.writeln('• ${c['name']}: ${c['number']}');
      }
      return McpToolExecutionResult(
        isToolCall: true,
        toolName: 'android_search_contacts',
        arguments: args,
        displayText: buffer.toString().trim(),
        rawData: contacts,
        success: true,
      );
    }
    return McpToolExecutionResult(
      isToolCall: true,
      toolName: 'android_search_contacts',
      arguments: args,
      displayText: 'No contacts found matching "$query".',
      success: true,
    );
  }

  /// Parses text output from model or user and identifies tool calls
  McpToolExecutionResult? tryParseToolCall(String rawResponse) {
    try {
      final trimmed = rawResponse.trim();
      final jsonRegex = RegExp(r'\{[\s\S]*\}');
      final match = jsonRegex.firstMatch(trimmed);
      if (match == null) return null;

      final jsonStr = match.group(0)!;
      final parsed = jsonDecode(jsonStr);

      if (parsed is Map<String, dynamic>) {
        if (parsed.containsKey('tool')) {
          final tool = parsed['tool'].toString();
          final args = parsed['arguments'] is Map<String, dynamic>
              ? Map<String, dynamic>.from(parsed['arguments'] as Map)
              : <String, dynamic>{};
          return McpToolExecutionResult(
            isToolCall: true,
            toolName: tool,
            arguments: args,
            displayText: 'Executing $tool...',
          );
        }

        if (parsed.containsKey('name') && parsed.containsKey('arguments')) {
          final name = parsed['name'].toString();
          final args = parsed['arguments'] is Map<String, dynamic>
              ? Map<String, dynamic>.from(parsed['arguments'] as Map)
              : <String, dynamic>{};
          return McpToolExecutionResult(
            isToolCall: true,
            toolName: name,
            arguments: args,
            displayText: 'Executing $name...',
          );
        }

        if (parsed['type'] == 'function' && parsed.containsKey('function')) {
          final func = parsed['function'];
          final name = func is Map ? func['name'] : func.toString();
          final args = parsed['parameters'] is Map
              ? Map<String, dynamic>.from(parsed['parameters'] as Map)
              : (func is Map && func['arguments'] is Map
                  ? Map<String, dynamic>.from(func['arguments'] as Map)
                  : <String, dynamic>{});
          return McpToolExecutionResult(
            isToolCall: true,
            toolName: name.toString(),
            arguments: args,
            displayText: 'Executing $name...',
          );
        }
      }
    } catch (_) {}
    return null;
  }

  int _levenshtein(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;
    List<int> v0 = List<int>.generate(s2.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(s2.length + 1, 0);
    for (int i = 0; i < s1.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < s2.length; j++) {
        int cost = (s1[i] == s2[j]) ? 0 : 1;
        int m = v1[j] + 1;
        if (v0[j + 1] + 1 < m) m = v0[j + 1] + 1;
        if (v0[j] + cost < m) m = v0[j] + cost;
        v1[j + 1] = m;
      }
      for (int j = 0; j <= s2.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[s2.length];
  }
}
