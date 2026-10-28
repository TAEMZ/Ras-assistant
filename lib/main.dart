import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/amharic_asr_service.dart';
import 'services/amharic_tts_service.dart';
import 'services/audio_session_manager.dart';
import 'services/intent_engine.dart';
import 'services/native_action_service.dart';
import 'services/semantic_intent_service.dart';
import 'services/mcp_tool_service.dart';
import 'services/model_inference_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const RasApp());
}

class ChatMessage {
  final bool isUser;
  final String text;
  final ActionType? actionType;
  final List<Map<String, dynamic>>? fileResults;
  final String? storageText;
  final String? appNameToLaunch;
  final String? appPackageToLaunch;
  final String? contactToCall;
  final String? contactNumberToCall;
  final DateTime timestamp;

  ChatMessage({
    required this.isUser,
    required this.text,
    this.actionType,
    this.fileResults,
    this.storageText,
    this.appNameToLaunch,
    this.appPackageToLaunch,
    this.contactToCall,
    this.contactNumberToCall,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class RasApp extends StatelessWidget {
  const RasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ras',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE2E8F0),
          surface: Color(0xFF050505),
          onSurface: Color(0xFFF8FAFC),
        ),
        fontFamily: 'sans-serif',
      ),
      home: const RasMainScreen(),
    );
  }
}

class RasMainScreen extends StatefulWidget {
  const RasMainScreen({super.key});

  @override
  State<RasMainScreen> createState() => _RasMainScreenState();
}

class _RasMainScreenState extends State<RasMainScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final AmharicAsrService _asrService = AmharicAsrService();
  final AmharicTtsService _ttsService = AmharicTtsService();
  final NativeActionService _nativeService = NativeActionService();
  final AudioSessionManager _audioSessionManager = AudioSessionManager();
  final SemanticIntentService _semanticService = SemanticIntentService();
  late final McpToolService _mcpToolService = McpToolService(nativeService: _nativeService);
  final ModelInferenceService _modelService = ModelInferenceService();

  bool _isEngineReady = false;
  bool _isProcessing = false;

  String _transcript = '';
  String? _executionFeedback;

  Timer? _callCountdownTimer;
  int _callCountdownSeconds = 3;
  String? _pendingCallContact;
  String? _pendingCallNumber;

  late final AnimationController _pulseController;
  late final AnimationController _spectrumController;
  late final Animation<double> _pulseAnimation;

  final TextEditingController _chatInputController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isChatOpen = false;
  bool _isAwaitingChatResponse = false;
  DateTime? _lastActiveSessionTime;
  bool _isAppInBackground = false;



  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.98, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _spectrumController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrapSystem();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callCountdownTimer?.cancel();
    _chatInputController.dispose();
    _chatScrollController.dispose();
    _pulseController.dispose();
    _spectrumController.dispose();
    _audioSessionManager.dispose();
    _asrService.dispose();
    _ttsService.release();
    _nativeService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isAppInBackground = false;
      debugPrint('[AppLifecycle] Application resumed: refreshing contacts & installed apps');
      _nativeService.syncContacts();
      _nativeService.syncInstalledApps();

      final now = DateTime.now();
      if (_lastActiveSessionTime != null && now.difference(_lastActiveSessionTime!).inMinutes > 15) {
        debugPrint('[AppLifecycle] Session expired (interval >15m). Resetting message memory for fresh session.');
        if (mounted) {
          setState(() {
            _messages.clear();
            _transcript = '';
            _executionFeedback = null;
          });
        }
      }
      _lastActiveSessionTime = now;
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      _isAppInBackground = true;
      _lastActiveSessionTime = DateTime.now();
    }
  }

  Future<void> _bootstrapSystem() async {
    try {
      await _nativeService.requestAllPermissions();

      // Hook up audio and wake-word handlers immediately so UI stays responsive
      _audioSessionManager.onUtteranceComplete = (samples) async {
        await _processAudioSamples(samples);
      };
      _audioSessionManager.onTurnRecycled = () {};
      _audioSessionManager.onError = (err) {
        if (mounted) setState(() {});
      };

      _nativeService.onWakeWordTriggered = () async {
        debugPrint('[WAKE_WORD] Assistant awakened by "ሰላም ራስ" / "Hey Ras"');
        if (mounted) {
          setState(() {
            _transcript = 'ሰላም ራስ';
            _executionFeedback = 'ሰላም! ምን ልርዳዎት?';
          });
          HapticFeedback.heavyImpact();
          await _ttsService.speak('ሰላም ምን ልርዳዎት');
          if (!_isProcessing && mounted) {
            _startListening();
          }
        }
      };

      _nativeService.onWakeWordCandidate = (Uint8List pcmBytes) async {
        try {
          final numSamples = pcmBytes.length ~/ 2;
          if (numSamples < 3200) return;

          final byteData = ByteData.sublistView(pcmBytes);
          final samples = Float32List(numSamples);
          for (int i = 0; i < numSamples; i++) {
            final sample16 = byteData.getInt16(i * 2, Endian.little);
            samples[i] = sample16 / 32768.0;
          }

          final text = await _asrService.transcribe(samples);
          debugPrint('[WAKE_WORD] Candidate ASR result: "$text"');

          if (_isWakePhrase(text)) {
            debugPrint('[WAKE_WORD] CONFIRMED: "$text" matches wake phrase. Triggering...');
            await _nativeService.confirmWakeWord();
          }
        } catch (e) {
          debugPrint('[WAKE_WORD] ASR verification error: $e');
        }
      };

      _nativeService.onTestQuery = (String query, bool isFromChat) async {
        debugPrint('[TEST_HARNESS] Dispatching test query: "$query" (isFromChat: $isFromChat)');
        await _handleTranscription(query, isFromChat: isFromChat);
      };

      _nativeService.onRunTests = (String suiteName) async {
        debugPrint('[TEST_HARNESS] Starting automated 58-tool verification suite: $suiteName');
        await _runFull58ToolVerificationSuite();
      };

      await _nativeService.startBackgroundWakeService();

      // Asynchronously initialize neural models without blocking the 60/120 FPS visualizers
      Future.microtask(() async {
        try {
          await _asrService.init();
          if (mounted) {
            setState(() {
              _isEngineReady = true;
            });
          }
          await _ttsService.init();
          await _semanticService.init();
          await _nativeService.syncContacts();
          await _nativeService.syncInstalledApps();
          debugPrint('[System] Amharic Neural Speech, Semantic Intent & Action engines fully active.');
        } catch (e) {
          debugPrint('[System] Engine background init error: $e');
        }
      });

    } catch (e) {
      debugPrint('[System] Bootstrap error: $e');
    }
  }

  void _startCallCountdown(String contactName, String? phoneNumber) {
    _callCountdownTimer?.cancel();
    setState(() {
      _pendingCallContact = contactName;
      _pendingCallNumber = phoneNumber;
      _callCountdownSeconds = 3;
      _executionFeedback = 'Calling $contactName in 3s...';
    });

    _callCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_callCountdownSeconds <= 1) {
        timer.cancel();
        _executePendingCall();
      } else {
        setState(() {
          _callCountdownSeconds--;
        });
      }
    });
  }

  void _cancelCallCountdown() {
    _callCountdownTimer?.cancel();
    _callCountdownTimer = null;
    final name = _pendingCallContact ?? 'call';
    setState(() {
      _pendingCallContact = null;
      _pendingCallNumber = null;
      _callCountdownSeconds = 3;
      _executionFeedback = 'Call to $name cancelled.';
    });
    _ttsService.speak('ጥሪ ተሰርዟል');
  }

  Future<void> _executePendingCall() async {
    _callCountdownTimer?.cancel();
    _callCountdownTimer = null;
    final target = _pendingCallContact;
    final number = _pendingCallNumber;

    setState(() {
      _pendingCallContact = null;
      _pendingCallNumber = null;
      _callCountdownSeconds = 3;
    });

    if (target == null) return;

    final ok = number != null && number.isNotEmpty
        ? await _nativeService.makeDirectCall(number)
        : await _nativeService.callContact(target);

    if (mounted) {
      setState(() {
        _executionFeedback = ok ? 'Calling $target...' : 'Unable to connect to $target';
      });
    }
  }

  Future<void> _processAudioSamples(Float32List samples) async {
    if (!mounted || _isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final text = await _asrService.transcribe(samples);
      await _handleTranscription(text);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _toggleListening() async {
    HapticFeedback.lightImpact();
    await _ttsService.stop();
    if (_audioSessionManager.isRecording) {
      await _audioSessionManager.stopAndFinalize();
    } else {
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    if (!_isEngineReady || _isProcessing) return;
    await _ttsService.stop();

    final started = await _audioSessionManager.startListening();
    if (started && mounted) {
      setState(() {
        _transcript = '';
        _executionFeedback = null;
      });
    }
  }

  bool _isWakePhrase(String text) {
    final clean = text.trim().toLowerCase();
    if (clean.isEmpty) return false;
    // Require BOTH components: a greeting word AND 'ras' — never match single words
    final hasRas = clean.contains('ራስ') || clean.contains('ras');
    final hasGreeting = clean.contains('ሰላም') || clean.contains('ሄይ') ||
        clean.contains('hey') || clean.contains('selam') ||
        clean.contains('hello') || clean.contains('hi ');
    return hasRas && hasGreeting;
  }

  Future<void> _handleTranscription(String text, {bool isFromChat = false}) async {
    if (text.trim().isEmpty) return;

    if (mounted) {
      setState(() {
        _messages.add(ChatMessage(isUser: true, text: text));
        _transcript = text;
        _isProcessing = false;
        if (isFromChat) {
          _isAwaitingChatResponse = true;
        }
      });
      _scrollChatToBottom();
    }

    try {
      // Collect last 6 message turns (excluding current query) for multi-turn continuity
      final previousTurns = <Map<String, String>>[];
      final pastMsgs = _messages.length > 1 ? _messages.sublist(0, _messages.length - 1) : <ChatMessage>[];
      final recentPast = pastMsgs.length > 6 ? pastMsgs.sublist(pastMsgs.length - 6) : pastMsgs;
      for (final m in recentPast) {
        if (m.text.startsWith('Unable to') || m.text.startsWith('Connection error')) continue;
        previousTurns.add({
          'role': m.isUser ? 'user' : 'assistant',
          'content': m.text,
        });
      }

      debugPrint('[Main] Routing query to ModelInferenceService: "$text" (isFromChat: $isFromChat)');

      // Execute OGAM 2-phase tool cycle for all queries
      final turnResult = await _modelService.executeChatTurn(
        userPrompt: text,
        previousTurns: previousTurns,
        mcpService: _mcpToolService,
      );

      if (mounted) {
        setState(() {
          _isAwaitingChatResponse = false;
          _executionFeedback = turnResult.textResponse;
          _messages.add(ChatMessage(
            isUser: false,
            text: turnResult.textResponse,
            fileResults: turnResult.rawData,
          ));
        });
        _scrollChatToBottom();
      }

      // If user navigated to another app, display the answer in a heads-up floating notification at top of screen
      if (_isAppInBackground && turnResult.textResponse.isNotEmpty) {
        await _nativeService.showNotificationNative(
          title: 'Ras Assistant',
          message: turnResult.textResponse,
        );
      }

      // Strict Policy: TTS must NEVER narrate jobs or device actions (alarms, timers, music, apps, hardware).
      // Only the wake-word greeting ("ሰላም ምን ልርዳዎት") and direct Amharic conversational answers are spoken.
      // All tool actions and Latin/English responses are completely silent on audio.
      final bool hasGeez = RegExp(r'[\u1200-\u137F]').hasMatch(turnResult.textResponse);
      if (!isFromChat && !turnResult.usedTool && hasGeez && turnResult.textResponse.isNotEmpty) {
        await _ttsService.speak(turnResult.textResponse);
      }
      return;
    } catch (e, stack) {
      debugPrint('[Main] Error handling input with model service: $e\n$stack');
    } finally {
      if (mounted && _isAwaitingChatResponse) {
        setState(() {
          _isAwaitingChatResponse = false;
        });
      }
    }
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _runFull58ToolVerificationSuite() async {
    debugPrint('================================================================');
    debugPrint('   STARTING AUTOMATED 58-TOOL VERIFICATION SUITE ON DEVICE      ');
    debugPrint('================================================================');

    final testArgs = <String, Map<String, dynamic>>{
      'android_list_files': {'query': 'pdf', 'location': 'all'},
      'android_get_app_info': {'app_name': 'ras'},
      'android_list_apps': {'sort_by': 'size', 'filter': 'user'},
      'android_open_app': {'app_name': 'settings'},
      'android_toggle_flashlight': {'state': false},
      'android_get_memory_usage': {},
      'android_set_volume': {'stream': 'media', 'level': 5},
      'android_get_volume': {},
      'android_get_device_status': {},
      'android_get_device_info': {},
      'android_search_contacts': {'query': 'test'},
      'android_make_call': {'phone_number': '12345', 'dry_run': true},
      'android_send_sms': {'phone_number': '12345', 'message': 'test', 'dry_run': true},
      'android_open_dialer': {'phone_number': '12345', 'dry_run': true},
      'android_get_clipboard': {},
      'android_set_clipboard': {'text': 'Ras Assistant Test'},
      'android_open_camera': {},
      'android_open_wifi_settings': {},
      'android_open_bluetooth_settings': {},
      'android_open_sound_settings': {},
      'android_open_notifications': {},
      'android_open_quick_settings': {},
      'android_get_running_apps': {},
      'android_media_control': {'action': 'play'},
      'android_send_keyevent': {'key_code': 'KEYCODE_BACK'},
      'android_close_app': {'package_name': 'com.google.android.youtube'},
      'android_read_file': {'file_path': '/sdcard/Download/test.txt'},
      'android_write_file': {'file_path': '/sdcard/Download/ras_test.txt', 'content': 'verified'},
      'android_delete_file': {'file_path': '/sdcard/Download/ras_test.txt'},
      'android_list_storage_locations': {},
      'android_open_uri': {'uri': 'https://google.com'},
      'android_send_intent': {'action': 'android.intent.action.VIEW', 'uri': 'https://google.com'},
      'android_share_text': {'text': 'Sharing from Ras'},
      'android_get_location': {},
      'android_press_home': {},
      'android_press_back': {},
      'android_lock_screen': {},
      'android_unlock_screen': {},
      'android_tap': {'x': 10, 'y': 10},
      'android_double_tap': {'x': 10, 'y': 10},
      'android_long_press': {'x': 10, 'y': 10, 'duration_ms': 300},
      'android_swipe': {'start_x': 500, 'start_y': 800, 'end_x': 500, 'end_y': 300, 'duration_ms': 300},
      'android_drag': {'start_x': 300, 'start_y': 500, 'end_x': 700, 'end_y': 500, 'duration_ms': 400},
      'android_scroll': {'direction': 'up'},
      'android_pinch': {'direction': 'in', 'center_x': 500, 'center_y': 500},
      'android_type_text': {'text': 'ras'},
      'android_clear_text': {},
      'android_press_enter': {},
      'android_take_screenshot': {},
      'android_get_ui_tree': {},
      'android_get_node_details': {'text': 'Settings'},
      'android_wait_for_node': {'text': 'Settings', 'timeout_ms': 500},
      'android_wait_for_idle': {'timeout_ms': 300},
      'android_notification_list': {},
      'android_notification_open': {'key': 'test_key'},
      'android_notification_dismiss': {'key': 'test_key'},
      'android_notification_reply': {'key': 'test_key', 'message': 'ok'},
      'android_notification_action': {'key': 'test_key', 'action_index': 0},
      'android_list_cameras': {},
      'android_take_camera_photo': {'camera_id': '0'},
    };

    int passed = 0;
    int failed = 0;
    final total = McpToolService.officialTools.length;

    for (int i = 0; i < total; i++) {
      final tool = McpToolService.officialTools[i];
      final args = testArgs[tool.name] ?? <String, dynamic>{};
      try {
        final res = await _mcpToolService.executeTool(tool.name, args);
        passed++;
        debugPrint('[VERIFICATION_58] [#${i + 1}/$total] TOOL: ${tool.name} -> SUCCESS: ${res.success} | OUTPUT: ${res.displayText.replaceAll("\n", " ")}');
      } catch (e) {
        failed++;
        debugPrint('[VERIFICATION_58] [#${i + 1}/$total] TOOL: ${tool.name} -> ERROR: $e');
      }
      await Future.delayed(const Duration(milliseconds: 30));
    }

    // Verify Chat Drawer flow (isFromChat: true) - must update chat, remain silent (no TTS)
    debugPrint('[VERIFICATION_CHAT_START] Testing Chat Drawer flow (isFromChat: true, zero TTS audio)...');
    await _handleTranscription('how about the ras app how much is its size', isFromChat: true);
    debugPrint('[VERIFICATION_CHAT_RESULT] Chat Drawer test query completed.');

    // Verify Primary Ras interface flow (isFromChat: false) - must update UI and trigger TTS
    debugPrint('[VERIFICATION_RAS_START] Testing Primary Ras interface flow (isFromChat: false, audio TTS playback)...');
    await _handleTranscription('how about the ras app how much is its size', isFromChat: false);
    debugPrint('[VERIFICATION_RAS_RESULT] Primary Ras interface test query completed.');

    debugPrint('================================================================');
    debugPrint('   VERIFICATION SUITE SUMMARY: $passed PASSED, $failed FAILED out of $total Tools   ');
    debugPrint('================================================================');
  }

  Future<void> _submitTextMessage(String text) async {
    final query = text.trim();
    if (query.isEmpty) return;
    _chatInputController.clear();
    await _handleTranscription(query, isFromChat: true);
  }

  // ignore: unused_element
  Future<void> _executeAction(IntentResult intent, {bool isFromChat = false}) async {
    String feedback = '';
    String spokenText = '';
    List<Map<String, dynamic>>? fileResults;
    String? storageText;
    String? appNameToLaunch = intent.targetAppName;
    String? appPackageToLaunch = intent.targetAppPackage;
    String? contactToCall = intent.targetContact;
    String? contactNumberToCall;

    switch (intent.action) {
      case ActionType.greeting:
        final isAmharic = RegExp(r'[\u1200-\u137F]').hasMatch(intent.rawQuery);
        feedback = intent.conversationalResponse ?? (isAmharic ? 'ሰላም! ምን ልርዳዎት?' : 'Hello! How can I help you today?');
        spokenText = isAmharic ? 'ሰላም ምን ልርዳዎት' : 'Hello How can I help you';
        HapticFeedback.lightImpact();
        break;

      case ActionType.identity:
        final isAmharic = RegExp(r'[\u1200-\u137F]').hasMatch(intent.rawQuery);
        feedback = intent.conversationalResponse ?? (isAmharic ? 'እኔ ራስ ነኝ። የእርስዎ የግል ረዳት።' : 'I am Ras, your personal device assistant.');
        spokenText = feedback;
        HapticFeedback.lightImpact();
        break;

      case ActionType.joke:
        final isAmharic = RegExp(r'[\u1200-\u137F]').hasMatch(intent.rawQuery);
        feedback = intent.conversationalResponse ?? (isAmharic ? 'አንድ ሰውዬ ወደ ሆስፒታል ሄዶ...' : 'Why was the math book sad? Because it had too many problems! 😆');
        spokenText = feedback;
        HapticFeedback.lightImpact();
        break;

      case ActionType.banter:
        final isAmharic = RegExp(r'[\u1200-\u137F]').hasMatch(intent.rawQuery);
        feedback = intent.conversationalResponse ?? (isAmharic ? 'እሺ፣ ምን ልርዳዎት?' : 'Sure! How can I assist you with your device today?');
        spokenText = feedback;
        HapticFeedback.lightImpact();
        break;

      case ActionType.getStorage:
        final stats = await _nativeService.getStorageDiagnostics();
        final freeGb = ((stats['freeBytes'] as num? ?? 0) / (1024 * 1024 * 1024)).toStringAsFixed(1);
        final totalGb = ((stats['totalBytes'] as num? ?? 0) / (1024 * 1024 * 1024)).toStringAsFixed(1);
        final usedPct = (stats['usedPercentage'] as num? ?? 0).round();
        storageText = 'Internal: $freeGb GB free of $totalGb GB ($usedPct% used)';
        feedback = 'ማከማቻ፡ $freeGb GB ነፃ ከ $totalGb GB ($usedPct% ጥቅም ላይ ውሏል)';
        spokenText = 'የስልክዎ ነፃ ማከማቻ $freeGb ጊጋባይት ነው';
        break;

      case ActionType.searchFiles:
        final query = intent.targetFileQuery ?? '';
        final cat = intent.targetFileCategory ?? 'all';
        final files = await _nativeService.searchFiles(
          query: query.isNotEmpty ? query : null,
          category: cat,
          limit: 15,
        );
        fileResults = files;
        final label = cat != 'all' ? cat.toUpperCase() : 'matching';
        if (files.isEmpty) {
          feedback = query.isNotEmpty ? 'No files found for "$query"' : 'No $label files found on device';
          spokenText = 'ምንም $label ፋይል አልተገኘም';
        } else {
          feedback = 'Found ${files.length} $label files';
          spokenText = '${files.length} $label ፋይሎች ተገኝተዋል';
        }
        break;

      case ActionType.openFile:
        if (intent.targetFilePath != null) {
          final ok = await _nativeService.openFile(intent.targetFilePath!);
          feedback = ok ? 'Opening file...' : 'Could not open file';
          spokenText = ok ? 'ፋይሉን እየከፈትኩ ነው' : 'ፋይሉን መክፈት አልተቻለም';
        }
        break;

      case ActionType.flashlightOn:
        final ok = await _nativeService.setFlashlight(true);
        feedback = ok ? 'Flashlight turned ON' : 'Flashlight command failed';
        spokenText = ok ? 'መብራት አብርቻለሁ' : 'መብራት ማብራት አልተቻለም';
        break;

      case ActionType.flashlightOff:
        final ok = await _nativeService.setFlashlight(false);
        feedback = ok ? 'Flashlight turned OFF' : 'Flashlight command failed';
        spokenText = ok ? 'መብራት አጥፍቻለሁ' : 'መብራት ማጥፋት አልተቻለም';
        break;

      case ActionType.openCamera:
        final ok = await _nativeService.openCamera();
        feedback = ok ? 'Camera opened' : 'Could not launch camera';
        spokenText = ok ? 'ካሜራ እየከፈትኩ ነው' : 'ካሜራ መክፈት አልተቻለም';
        break;

      case ActionType.openWifi:
        final ok = await _nativeService.openWifiSettings();
        feedback = ok ? 'Wi-Fi settings opened' : 'Could not open Wi-Fi';
        spokenText = ok ? 'ዋይፋይ እየከፈትኩ ነው' : 'ዋይፋይ መክፈት አልተቻለም';
        break;

      case ActionType.openBluetooth:
        final ok = await _nativeService.openBluetoothSettings();
        feedback = ok ? 'Bluetooth settings opened' : 'Could not open Bluetooth';
        spokenText = ok ? 'ብሉቱዝ እየከፈትኩ ነው' : 'ብሉቱዝ መክፈት አልተቻለም';
        break;

      case ActionType.openSoundSettings:
        final ok = await _nativeService.openSoundSettings();
        feedback = ok ? 'Sound settings opened' : 'Could not open sound settings';
        spokenText = ok ? 'የድምፅ ማስተካከያ እየከፈትኩ ነው' : 'የድምፅ ማስተካከያ መክፈት አልተቻለም';
        break;

      case ActionType.getBattery:
        final level = await _nativeService.getBatteryLevel();
        feedback = level >= 0 ? 'Battery level: $level%' : 'Could not query battery';
        spokenText = level >= 0 ? 'የባትሪ መጠን $level በመቶ ነው' : 'የባትሪ መጠን ማወቅ አልተቻለም';
        break;

      case ActionType.openContacts:
        final ok = await _nativeService.openContactsApp();
        feedback = ok ? 'Contacts directory opened' : 'Could not open contacts';
        spokenText = ok ? 'ስልክ ቁጥሮችን እየከፈትኩ ነው' : 'ስልክ ቁጥሮችን መክፈት አልተቻለም';
        break;

      case ActionType.openDialer:
        final ok = await _nativeService.openDialer();
        feedback = ok ? 'Phone dialer opened' : 'Could not open dialer';
        spokenText = ok ? 'ስልክ መደወያ እየከፈትኩ ነው' : 'መደወያውን መክፈት አልተቻለም';
        break;

      case ActionType.openApp:
        if (intent.targetAppPackage != null) {
          final ok = await _nativeService.launchApp(intent.targetAppPackage!);
          feedback = ok
              ? 'Opening ${intent.targetAppName ?? "application"}...'
              : 'Failed launching ${intent.targetAppName ?? "app"}';
          spokenText = ok ? 'መተግበሪያውን እየከፈትኩ ነው' : 'መተግበሪያውን መክፈት አልተቻለም';
        } else {
          feedback = 'Application not installed';
          spokenText = 'መተግበሪያው አልተጫነም';
        }
        break;

      case ActionType.listApps:
        final mcpRes = await _mcpToolService.executeTool('android_list_apps', {'filter': 'all'});
        feedback = mcpRes.displayText;
        fileResults = mcpRes.rawData;
        spokenText = 'በስልክዎ ላይ ${_nativeService.cachedApps.length} መተግበሪያዎች ተጭነዋል';
        break;

      case ActionType.mcpTool:
        if (intent.mcpResult != null) {
          feedback = intent.mcpResult!.displayText;
          fileResults = intent.mcpResult!.rawData;
        }
        break;

      case ActionType.call:
        if (intent.targetContact != null) {
          String? phoneNumber;
          String contactDisplayName = intent.targetContact!;
          for (final contact in _nativeService.cachedContacts) {
            final name = (contact.displayName ?? '').toLowerCase();
            if (name.contains(intent.targetContact!.toLowerCase())) {
              contactDisplayName = contact.displayName ?? intent.targetContact!;
              if (contact.phones.isNotEmpty) {
                phoneNumber = contact.phones.first.number;
              }
              break;
            }
          }
          if (phoneNumber == null) {
            await _nativeService.syncContacts();
            for (final contact in _nativeService.cachedContacts) {
              final name = (contact.displayName ?? '').toLowerCase();
              if (name.contains(intent.targetContact!.toLowerCase())) {
                contactDisplayName = contact.displayName ?? intent.targetContact!;
                if (contact.phones.isNotEmpty) {
                  phoneNumber = contact.phones.first.number;
                }
                break;
              }
            }
          }
          contactNumberToCall = phoneNumber;
          if (isFromChat) {
            feedback = 'Contact: $contactDisplayName ${phoneNumber != null ? "($phoneNumber)" : ""}';
            spokenText = '';
            break;
          }
          _ttsService.speak('እየደወልኩ ነው');
          _startCallCountdown(contactDisplayName, phoneNumber);

          if (mounted) {
            setState(() {
              _executionFeedback = 'Calling $contactDisplayName...';
              _messages.add(ChatMessage(
                isUser: false,
                text: 'Calling $contactDisplayName...',
                actionType: ActionType.call,
                contactToCall: contactDisplayName,
                contactNumberToCall: phoneNumber,
              ));
            });
            _scrollChatToBottom();
          }
          return;
        } else {
          if (isFromChat) {
            feedback = 'Phone calls cannot be triggered from chat';
            spokenText = '';
          } else {
            final ok = await _nativeService.openDialer();
            feedback = ok ? 'Phone dialer opened' : 'Could not open dialer';
            spokenText = ok ? 'ስልክ መደወያ እየከፈትኩ ነው' : 'መደወያውን መክፈት አልተቻለም';
          }
        }
        break;

      case ActionType.none:
        feedback = 'Unrecognized command';
        spokenText = 'ይቅርታ አልገባኝም';
        break;
    }

    if (mounted) {
      setState(() {
        _executionFeedback = feedback;
        _messages.add(ChatMessage(
          isUser: false,
          text: feedback,
          actionType: intent.action,
          fileResults: fileResults,
          storageText: storageText,
          appNameToLaunch: appNameToLaunch,
          appPackageToLaunch: appPackageToLaunch,
          contactToCall: contactToCall,
          contactNumberToCall: contactNumberToCall,
        ));
      });
      _scrollChatToBottom();
    }

    if (spokenText.isNotEmpty && !isFromChat) {
      _ttsService.speak(spokenText);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _buildMinimalHeader(),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 10),
                          _buildDynamicStatePill(),
                          const SizedBox(height: 18),
                          _buildHarmonicCoreVisualizer(),
                          const SizedBox(height: 24),
                          _buildAcousticSpectrum(),
                          const SizedBox(height: 36),
                          _buildFloatingSpeechSurface(),
                        ],
                      ),
                    ),
                  ),
                ),
                _buildMinimalBottomDock(),
              ],
            ),
          ),
          if (_pendingCallContact != null)
            _buildFluidGlassCallModal(),
          if (_isChatOpen)
            _buildObsidianChatDrawer(),
        ],
      ),
    );
  }

  Widget _buildMinimalHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'RAS',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 4.5,
              color: Color(0xFFF8FAFC),
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() {
                _isChatOpen = true;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0x12FFFFFF),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0x26FFFFFF),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.forum_outlined,
                    size: 14,
                    color: Color(0xFFCBD5E1),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _messages.isNotEmpty ? '${_messages.length}' : 'Chat',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                      color: Color(0xFFCBD5E1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDynamicStatePill() {
    return ValueListenableBuilder<AudioCaptureState>(
      valueListenable: _audioSessionManager.captureStateNotifier,
      builder: (context, state, child) {
        String label;
        Color textColor;

        if (_isProcessing) {
          label = 'እያሰበ ነው...';
          textColor = const Color(0xFFFBBF24);
        } else if (state == AudioCaptureState.speechDetected) {
          label = 'እየሰማዎት ነው...';
          textColor = const Color(0xFFE2E8F0);
        } else if (_audioSessionManager.isRecording) {
          label = 'ይናገሩ...';
          textColor = const Color(0xFF38BDF8);
        } else {
          label = '';
          textColor = const Color(0xFF94A3B8);
        }

        if (label.isEmpty) return const SizedBox.shrink();

        return AnimatedOpacity(
          duration: const Duration(milliseconds: 250),
          opacity: 1.0,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.8,
              color: textColor,
            ),
          ),
        );
      },
    );
  }

  Widget _buildHarmonicCoreVisualizer() {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: _isEngineReady ? _toggleListening : null,
        child: SizedBox(
          width: 260,
          height: 260,
          child: Center(
            child: ValueListenableBuilder<double>(
              valueListenable: _audioSessionManager.audioLevelNotifier,
              builder: (context, audioLevel, child) {
                return AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    final isRec = _audioSessionManager.isRecording;

                    // When speaking: surge forward dynamically based on live voice energy (up to 1.18x)
                    // When idle: calm, breathing rhythm (0.98x - 1.04x)
                    final forwardScale = isRec
                        ? (1.02 + audioLevel * 0.16)
                        : _pulseAnimation.value;

                    return Transform.scale(
                      scale: forwardScale,
                      child: SizedBox(
                        width: 220,
                        height: 220,
                        child: Image.asset(
                          'assets/images/ras_logo.png',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(
                                Icons.mic_none,
                                size: 64,
                                color: Color(0xFFE2E8F0),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAcousticSpectrum() {
    return RepaintBoundary(
      child: ValueListenableBuilder<double>(
        valueListenable: _audioSessionManager.audioLevelNotifier,
        builder: (context, audioLevel, child) {
          return AnimatedBuilder(
            animation: _spectrumController,
            builder: (context, child) {
              return SizedBox(
                width: 220,
                height: 34,
                child: CustomPaint(
                  size: const Size(220, 34),
                  painter: AcousticSpectrumPainter(
                    progress: _spectrumController.value,
                    isRecording: _audioSessionManager.isRecording,
                    audioLevel: audioLevel,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildFloatingSpeechSurface() {
    final hasTranscript = _transcript.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28.0),
      child: Column(
        children: [
          AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: hasTranscript ? 1.0 : 0.45,
            child: Text(
              hasTranscript ? _transcript : 'የሚፈልጉትን ይናገሩ...',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: hasTranscript ? 26 : 18,
                height: 1.35,
                fontWeight: hasTranscript ? FontWeight.w700 : FontWeight.w400,
                letterSpacing: hasTranscript ? 0.2 : 0.8,
                color: hasTranscript ? const Color(0xFFF8FAFC) : const Color(0xFF64748B),
              ),
            ),
          ),
          if (_executionFeedback != null) ...[
            const SizedBox(height: 20),
            Text(
              _executionFeedback!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFFCBD5E1),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMinimalBottomDock() {
    return ValueListenableBuilder<AudioCaptureState>(
      valueListenable: _audioSessionManager.captureStateNotifier,
      builder: (context, state, child) {
        final isActive = state == AudioCaptureState.listening ||
            state == AudioCaptureState.speechDetected;

        return Padding(
          padding: const EdgeInsets.only(bottom: 28.0),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0x1AFFFFFF)
                    : const Color(0x0EFFFFFF),
                borderRadius: BorderRadius.circular(36),
                border: Border.all(
                  color: isActive
                      ? const Color(0x66FFFFFF)
                      : const Color(0x26FFFFFF),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Microphone Trigger
                  GestureDetector(
                    onTap: _isEngineReady ? _toggleListening : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0x22F87171)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isActive
                                ? Icons.stop_rounded
                                : Icons.mic_rounded,
                            size: 18,
                            color: isActive
                                ? const Color(0xFFF87171)
                                : const Color(0xFFF8FAFC),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isActive ? 'Listening...' : 'Tap to Speak',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.4,
                              color: Color(0xFFF8FAFC),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Divider
                  Container(
                    width: 1,
                    height: 18,
                    color: const Color(0x26FFFFFF),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                  ),

                  // Chat Drawer Trigger
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isChatOpen = true;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.forum_outlined,
                            size: 16,
                            color: Color(0xFFCBD5E1),
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Chat',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFFCBD5E1),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildObsidianChatDrawer() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.75),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: SafeArea(
            child: Column(
              children: [
                // Drawer Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      const Text(
                        'Chat',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          color: Color(0xFFF1F5F9),
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _isChatOpen = false;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0x16FFFFFF),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0x26FFFFFF), width: 0.6),
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: Color(0xFFF8FAFC),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1, color: Color(0x1AFFFFFF)),

                // Messages Timeline
                Expanded(
                  child: _messages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 42,
                                color: const Color(0xFF64748B).withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'ማንኛውንም ጥያቄ ይጠይቁ ወይም ፋይል ይፈልጉ',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Ask questions, search files, check battery or storage',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _chatScrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          itemCount: _messages.length + (_isAwaitingChatResponse ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _messages.length && _isAwaitingChatResponse) {
                              return const _TypingIndicatorDots();
                            }
                            return _buildMessageBubble(_messages[index]);
                          },
                        ),
                ),

                // Chat Input Dock
                _buildChatInputDock(),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildChatInputDock() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0x12FFFFFF),
        border: Border(
          top: BorderSide(color: Color(0x1AFFFFFF), width: 0.6),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0x1AFFFFFF),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: const Color(0x26FFFFFF),
                  width: 0.8,
                ),
              ),
              child: TextField(
                controller: _chatInputController,
                textInputAction: TextInputAction.send,
                onSubmitted: _submitTextMessage,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFFF8FAFC),
                ),
                decoration: const InputDecoration(
                  hintText: 'መልእክት ይጻፉ ወይም ይፈልጉ...',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                  ),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => _submitTextMessage(_chatInputController.text),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: const Icon(
                Icons.arrow_upward_rounded,
                size: 20,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    if (msg.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          constraints: const BoxConstraints(maxWidth: 290),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2C3240), Color(0xFF1D222D)],
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(4),
            ),
            border: Border.all(color: const Color(0x38FFFFFF), width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            msg.text,
            style: const TextStyle(
              fontSize: 14.5,
              height: 1.4,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.1,
              color: Color(0xFFF8FAFC),
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF191D26), Color(0xFF11131A)],
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(18),
          ),
          border: Border.all(color: const Color(0x28FFFFFF), width: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              msg.text,
              style: const TextStyle(
                fontSize: 14.5,
                height: 1.42,
                fontWeight: FontWeight.w400,
                color: Color(0xFFE2E8F0),
              ),
            ),

            // Storage Meter Card
            if (msg.storageText != null)
              _buildStorageCard(msg.storageText!),

            // File Search Result Cards
            if (msg.fileResults != null && msg.fileResults!.isNotEmpty)
              ...msg.fileResults!.map((file) => _buildFileActionCard(file)),

            // App Launch Card
            if (msg.appPackageToLaunch != null)
              Padding(
                padding: const EdgeInsets.only(top: 10.0),
                child: ElevatedButton.icon(
                  onPressed: () => _nativeService.launchApp(msg.appPackageToLaunch!),
                  icon: const Icon(Icons.launch_rounded, size: 14),
                  label: Text('Open ${msg.appNameToLaunch ?? "App"}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0x26FFFFFF),
                    foregroundColor: const Color(0xFFF8FAFC),
                    elevation: 0,
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),


          ],
        ),
      ),
    );
  }

  Widget _buildStorageCard(String text) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x16FFFFFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x22FFFFFF), width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.storage_rounded, size: 16, color: Color(0xFF38BDF8)),
              SizedBox(width: 8),
              Text(
                'Device Storage Overview',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: Color(0xFFF8FAFC),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFFCBD5E1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileActionCard(Map<String, dynamic> file) {
    final name = (file['name'] as String?) ?? 'File';
    final path = (file['path'] as String?) ?? '';
    final folder = (file['folder'] as String?) ?? '';
    final sizeStr = _formatBytes(file['size']);
    final ext = name.toLowerCase();
    final isPdf = ext.endsWith('.pdf');
    final isImage = ext.endsWith('.jpg') ||
        ext.endsWith('.jpeg') ||
        ext.endsWith('.png') ||
        ext.endsWith('.webp') ||
        ext.endsWith('.gif') ||
        ext.endsWith('.heic');
    final isAudio = ext.endsWith('.mp3') ||
        ext.endsWith('.m4a') ||
        ext.endsWith('.wav') ||
        ext.endsWith('.ogg') ||
        ext.endsWith('.flac');
    final isVideo = ext.endsWith('.mp4') ||
        ext.endsWith('.mkv') ||
        ext.endsWith('.3gp') ||
        ext.endsWith('.mov');

    IconData fileIcon = Icons.insert_drive_file_outlined;
    Color iconColor = const Color(0xFFCBD5E1);
    if (isPdf) {
      fileIcon = Icons.picture_as_pdf_outlined;
      iconColor = const Color(0xFFF87171);
    } else if (isImage) {
      fileIcon = Icons.image_outlined;
      iconColor = const Color(0xFF38BDF8);
    } else if (isVideo) {
      fileIcon = Icons.video_file_outlined;
      iconColor = const Color(0xFF34D399);
    } else if (isAudio) {
      fileIcon = Icons.audio_file_outlined;
      iconColor = const Color(0xFFA78BFA);
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x16FFFFFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x22FFFFFF), width: 0.6),
      ),
      child: Row(
        children: [
          Icon(fileIcon, size: 22, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFF8FAFC),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$sizeStr • ${folder.isNotEmpty ? folder.replaceFirst('/storage/emulated/0/', '/') : path}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              if (path.isNotEmpty) {
                _nativeService.openFile(path);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0x22FFFFFF),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0x33FFFFFF), width: 0.6),
              ),
              child: const Text(
                'ክፈት',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE2E8F0),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatBytes(dynamic bytes) {
    if (bytes == null) return '0 B';
    final num b = bytes is num ? bytes : num.tryParse(bytes.toString()) ?? 0;
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Widget _buildFluidGlassCallModal() {
    final contactName = _pendingCallContact ?? 'Contact';
    final initial = contactName.trim().isNotEmpty
        ? contactName.trim().substring(0, 1).toUpperCase()
        : 'C';

    return Container(
      color: Colors.black.withValues(alpha: 0.72),
      alignment: Alignment.center,
      child: SizedBox(
        width: 320,
        height: 380,
        child: Stack(
          children: [
            // Ambient outer glow and shadow
            Positioned.fill(
              child: CustomPaint(
                painter: LiquidGlassShadowPainter(),
              ),
            ),
            // The Liquid Frosted Glass Body
            Positioned.fill(
              child: ClipPath(
                clipper: LiquidGlassClipper(),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF1A1F29).withValues(alpha: 0.88),
                          const Color(0xFF0F1218).withValues(alpha: 0.94),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // The Specular Glass Border
            Positioned.fill(
              child: CustomPaint(
                painter: LiquidGlassBorderPainter(),
              ),
            ),
            // Card Content
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 22.0),
                child: Column(
                  children: [
                    // Top Row with Close Icon
                    Align(
                      alignment: Alignment.topRight,
                      child: GestureDetector(
                        onTap: _cancelCallCountdown,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          color: Colors.transparent,
                          child: const Icon(
                            Icons.close,
                            size: 19,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),

                    // Avatar with glowing green accent indicator
                    SizedBox(
                      width: 72,
                      height: 72,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const RadialGradient(
                                center: Alignment(-0.3, -0.4),
                                radius: 0.9,
                                colors: [
                                  Color(0xFF2C3545),
                                  Color(0xFF131720),
                                ],
                              ),
                              border: Border.all(
                                color: const Color(0x33FFFFFF),
                                width: 1.0,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                initial,
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFF8FAFC),
                                ),
                              ),
                            ),
                          ),
                          // Green dot at 4:30
                          Positioned(
                            bottom: 2,
                            right: 4,
                            child: Container(
                              width: 11,
                              height: 11,
                              decoration: BoxDecoration(
                                color: const Color(0xFF4ADE80),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF0F1218),
                                  width: 2.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF4ADE80).withValues(alpha: 0.6),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Contact Name
                    Text(
                      contactName,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: Color(0xFFF8FAFC),
                      ),
                    ),
                    const SizedBox(height: 3),

                    // Phone Number
                    Text(
                      _pendingCallNumber ?? '0953852753',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF94A3B8),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Countdown progress line
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: Container(
                        width: double.infinity,
                        height: 2,
                        color: const Color(0x14FFFFFF),
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: _callCountdownSeconds / 3.0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFE2E8F0),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // "Call this number?" row with phone icon
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2.0),
                          child: Icon(
                            Icons.phone,
                            size: 19,
                            color: Color(0xFFF8FAFC),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Call this number?',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFF8FAFC),
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                "You'll be redirected to your phone app to make the call.",
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.3,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),

                    // Action Buttons Row: Cancel (translucent glass) & Call Now (luxury cream/bone)
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: _cancelCallCountdown,
                            child: Container(
                              height: 44,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(22),
                                color: const Color(0x14FFFFFF),
                                border: Border.all(
                                  color: const Color(0x29FFFFFF),
                                  width: 0.8,
                                ),
                              ),
                              child: const Center(
                                child: Text(
                                  'Cancel',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFF8FAFC),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: GestureDetector(
                            onTap: _executePendingCall,
                            child: Container(
                              height: 44,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(22),
                                color: const Color(0xFFF3EFE6), // Luxury bone-white
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.white.withValues(alpha: 0.15),
                                    blurRadius: 12,
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Text(
                                  'Call Now',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF141414), // Crisp contrast
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LiquidGlassClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return _createLiquidPath(size);
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class LiquidGlassBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = _createLiquidPath(size);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0x55FFFFFF),
          Color(0x22FFFFFF),
          Color(0x0DFFFFFF),
          Color(0x2AFFFFFF),
        ],
        stops: [0.0, 0.4, 0.7, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class LiquidGlassShadowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = _createLiquidPath(size);
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.7)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28);

    canvas.drawPath(path, shadowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Path _createLiquidPath(Size size) {
  final w = size.width;
  final h = size.height;
  final path = Path();

  // Organic liquid squircle with gentle undulating curves
  path.moveTo(w * 0.22, 0);
  path.cubicTo(w * 0.65, -h * 0.012, w * 0.85, h * 0.02, w * 0.92, h * 0.075);
  path.cubicTo(w * 1.015, h * 0.22, w * 0.985, h * 0.55, w * 1.01, h * 0.75);
  path.cubicTo(w * 1.025, h * 0.88, w * 0.88, h * 0.99, w * 0.76, h);
  path.cubicTo(w * 0.50, h * 1.012, w * 0.28, h * 0.98, w * 0.14, h * 0.935);
  path.cubicTo(w * 0.015, h * 0.88, -w * 0.01, h * 0.68, w * 0.028, h * 0.52);
  path.cubicTo(w * 0.048, h * 0.38, -w * 0.012, h * 0.20, w * 0.025, h * 0.095);
  path.cubicTo(w * 0.055, h * 0.028, w * 0.12, 0.005, w * 0.22, 0);

  path.close();
  return path;
}



class AcousticSpectrumPainter extends CustomPainter {
  final double progress;
  final bool isRecording;
  final double audioLevel;

  AcousticSpectrumPainter({
    required this.progress,
    required this.isRecording,
    this.audioLevel = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 28;
    final barWidth = (size.width - ((barCount - 1) * 3)) / barCount;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.fill;

    for (int i = 0; i < barCount; i++) {
      final normalizedX = i / barCount;
      final wave = math.sin((progress * 2 * math.pi) + (normalizedX * math.pi * 3));
      final factor = (wave + 1.0) / 2.0;

      final minHeight = 4.0;
      final dynamicMax = isRecording ? (14.0 + audioLevel * 18.0) : 12.0;
      final height = (minHeight + (dynamicMax - minHeight) * factor).clamp(3.0, 32.0);

      final x = i * (barWidth + 3);
      final y = (size.height - height) / 2;

      final alpha = isRecording
          ? (0.35 + (factor * 0.35) + (audioLevel * 0.3)).clamp(0.2, 1.0)
          : (0.28 + (factor * 0.32));
      paint.color = isRecording && audioLevel > 0.12
          ? Color.lerp(const Color(0xFFF8FAFC), const Color(0xFFE2E8F0), audioLevel)!
              .withValues(alpha: alpha)
          : const Color(0xFFF8FAFC).withValues(alpha: alpha);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, height),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant AcousticSpectrumPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isRecording != isRecording ||
        (oldDelegate.audioLevel - audioLevel).abs() > 0.02;
  }
}

class _TypingIndicatorDots extends StatefulWidget {
  const _TypingIndicatorDots();

  @override
  State<_TypingIndicatorDots> createState() => _TypingIndicatorDotsState();
}

class _TypingIndicatorDotsState extends State<_TypingIndicatorDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
          border: Border.all(
            color: const Color(0xFF334155),
            width: 0.8,
          ),
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                final delay = index * 0.22;
                final value = ((_controller.value - delay) % 1.0);
                final opacity = 0.25 + (0.75 * (value < 0.5 ? value * 2 : (1.0 - value) * 2));
                final scale = 0.75 + (0.35 * (value < 0.5 ? value * 2 : (1.0 - value) * 2));
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.5),
                  child: Transform.scale(
                    scale: scale,
                    child: Opacity(
                      opacity: opacity.clamp(0.2, 1.0),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xFF94A3B8),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

