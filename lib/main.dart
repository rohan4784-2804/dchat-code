import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

import 'notifications_service.dart';

const String baseUrl = 'https://dchat-pjz5.onrender.com';
// Keep these in sync with the version field in pubspec.yaml.
const String appVersion = '1.0.0';
const String appBuildNumber = '1';
const String appAuthor = 'Rohan Singh';
const String githubRepositoryUrl = 'https://github.com/rohan4784-2804/Dchat';
const String githubReleasesUrl = '$githubRepositoryUrl/releases';
const String latestReleaseApiUrl =
    'https://api.github.com/repos/rohan4784-2804/Dchat/releases/latest';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.initialize();
  runApp(const DChatApp());
}

class DChatApp extends StatelessWidget {
  const DChatApp({super.key});

  Future<void> openExternalUrl(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This link is not valid.')),
        );
      }
      return;
    }

    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the link.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open the link: ${errorText(e)}')),
        );
      }
    }
  }

  int compareVersions(String a, String b) {
    List<int> parts(String value) => value
        .trim()
        .replaceFirst(RegExp(r'^[vV]'), '')
        .split(RegExp(r'[.+-]'))
        .map((part) => int.tryParse(part) ?? 0)
        .toList();

    final left = parts(a);
    final right = parts(b);
    final count = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < count; i++) {
      final x = i < left.length ? left[i] : 0;
      final y = i < right.length ? right[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  Future<void> showAppInfo() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.forum_rounded, color: Color(0xFF9B93FF)),
            SizedBox(width: 10),
            Text('About DChat'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AppInfoLine(label: 'App name', value: 'DChat'),
            _AppInfoLine(label: 'Version', value: appVersion),
            _AppInfoLine(label: 'Build number', value: appBuildNumber),
            _AppInfoLine(label: 'Author', value: appAuthor),
            SizedBox(height: 12),
            Text('Release notes are available on the GitHub Releases page.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              openExternalUrl(githubReleasesUrl);
            },
            child: const Text('Release notes'),
          ),
        ],
      ),
    );
  }

  Future<void> checkForUpdates() async {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Expanded(child: Text('Checking for updates...')),
          ],
        ),
      ),
    );

    try {
      final response = await http.get(
        Uri.parse(latestReleaseApiUrl),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'DChat-Flutter-App',
        },
      ).timeout(const Duration(seconds: 20));

      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (!mounted) return;

      if (response.statusCode == 404) {
        await showReleaseDialog(
          title: 'No published releases yet',
          message:
              'DChat could not find a published GitHub release. You can open the Releases page to check manually.',
          releaseUrl: githubReleasesUrl,
        );
        return;
      }
      if (response.statusCode != 200) {
        throw Exception('GitHub returned HTTP ${response.statusCode}.');
      }

      final release = jsonDecode(response.body);
      if (release is! Map) throw Exception('GitHub returned invalid release data.');

      final tag = release['tag_name']?.toString().trim() ?? '';
      final releaseUrl = release['html_url']?.toString() ?? githubReleasesUrl;
      final notes = release['body']?.toString().trim() ?? '';
      if (tag.isEmpty) throw Exception('The latest release has no version tag.');

      final latestVersion = tag.replaceFirst(RegExp(r'^[vV]'), '');
      if (compareVersions(latestVersion, appVersion) <= 0) {
        await showReleaseDialog(
          title: 'You are up to date',
          message: 'Installed version: v$appVersion (build $appBuildNumber)\n'
              'Latest GitHub release: $tag\n\n'
              'There is no newer version available right now.',
          releaseUrl: releaseUrl,
          releaseNotes: notes,
        );
        return;
      }

      String? apkUrl;
      final assets = release['assets'];
      if (assets is List) {
        for (final asset in assets) {
          if (asset is Map) {
            final name = asset['name']?.toString() ?? '';
            final url = asset['browser_download_url']?.toString() ?? '';
            if (name.toLowerCase().endsWith('.apk') && url.startsWith('https://')) {
              apkUrl = url;
              break;
            }
          }
        }
      }

      await showReleaseDialog(
        title: 'There is an update of v$latestVersion',
        message: notes.isEmpty
            ? 'A newer DChat version is available. Open the release page for details.'
            : notes,
        releaseUrl: releaseUrl,
        apkUrl: apkUrl,
        releaseNotes: notes,
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
        await showReleaseDialog(
          title: 'Update check failed',
          message: '${errorText(e)}\n\nYou can check GitHub Releases manually.',
          releaseUrl: githubReleasesUrl,
        );
      }
    }
  }

  Future<void> showReleaseDialog({
    required String title,
    required String message,
    required String releaseUrl,
    String? apkUrl,
    String? releaseNotes,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(message.isEmpty ? 'No release notes were provided.' : message),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          if (apkUrl != null)
            FilledButton.tonal(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                openExternalUrl(apkUrl!);
              },
              child: const Text('Download APK'),
            ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              openExternalUrl(releaseUrl);
            },
            child: const Text('Open release notes'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DChat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF101018),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF9B93FF),
          brightness: Brightness.dark,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF20202C),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const DChatHome(),
    );
  }
}

class _AppInfoLine extends StatelessWidget {
  const _AppInfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(label, style: const TextStyle(color: Colors.white60)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

class DChatHome extends StatefulWidget {
  const DChatHome({super.key});

  @override
  State<DChatHome> createState() => _DChatHomeState();
}

class _DChatHomeState extends State<DChatHome> {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final messageController = TextEditingController();
  final messageScrollController = ScrollController();

  String? token;
  String? username;
  String? selectedUser;

  bool busy = false;
  bool isRegister = false;
  bool refreshingUsers = false;
  bool loadingMessages = false;
  bool sendingMessage = false;
  bool socketConnected = false;

  String error = '';

  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> messages = [];

  IO.Socket? socket;

  @override
  void initState() {
    super.initState();
    restoreSession();
  }

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    messageController.dispose();
    messageScrollController.dispose();
    socket?.disconnect();
    socket?.dispose();
    super.dispose();
  }

  bool sameUser(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  Map<String, dynamic> decodeResponse(http.Response response) {
    dynamic result;

    try {
      result = jsonDecode(response.body);
    } catch (_) {
      throw Exception(
        'Invalid server response (HTTP ${response.statusCode}).',
      );
    }

    if (result is! Map) {
      throw Exception('Unexpected response from server.');
    }

    return Map<String, dynamic>.from(result);
  }

  String errorText(Object e) =>
      e.toString().replaceFirst('Exception: ', '');

  Future<void> restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString('dchat_token');
      final savedUsername = prefs.getString('dchat_username');

      if (!mounted) return;

      if (savedToken != null &&
          savedToken.isNotEmpty &&
          savedUsername != null &&
          savedUsername.isNotEmpty) {
        setState(() {
          token = savedToken;
          username = savedUsername;
        });

        await NotificationService.instance.setAuthToken(savedToken);
        connectSocket();
        await refreshUsers(showFeedback: false);
      }
    } catch (e) {
      debugPrint('Session restore error: $e');
    }
  }

  Future<void> authenticate() async {
    final enteredUsername = usernameController.text.trim();
    final enteredPassword = passwordController.text;

    if (enteredUsername.isEmpty || enteredPassword.isEmpty) {
      setState(() => error = 'Enter your username and password.');
      return;
    }

    setState(() {
      busy = true;
      error = '';
    });

    try {
      final endpoint = isRegister ? '/api/register' : '/api/login';

      final response = await http
          .post(
            Uri.parse('$baseUrl$endpoint'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': enteredUsername,
              'password': enteredPassword,
            }),
          )
          .timeout(const Duration(seconds: 30));

      final data = decodeResponse(response);

      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          data['ok'] != true) {
        throw Exception(
          data['error']?.toString() ?? 'Authentication failed.',
        );
      }

      final receivedToken = data['token']?.toString();
      final userData = data['user'];
      final receivedUsername = userData is Map
          ? userData['username']?.toString()
          : null;

      if (receivedToken == null ||
          receivedToken.isEmpty ||
          receivedUsername == null ||
          receivedUsername.isEmpty) {
        throw Exception('The server did not return a valid session.');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('dchat_token', receivedToken);
      await prefs.setString('dchat_username', receivedUsername);

      if (!mounted) return;

      setState(() {
        token = receivedToken;
        username = receivedUsername;
        selectedUser = null;
        users = [];
        messages = [];
        error = '';
      });

      await NotificationService.instance.setAuthToken(receivedToken);
      connectSocket();
      await refreshUsers(showFeedback: false);
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void connectSocket() {
    final authToken = token;
    if (authToken == null || authToken.isEmpty) return;

    socket?.disconnect();
    socket?.dispose();

    socket = IO.io(
      baseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': authToken})
          .disableAutoConnect()
          .build(),
    );

    socket!.onConnect((_) {
      debugPrint('DChat connected: $username');

      if (mounted) setState(() => socketConnected = true);
      refreshUsers(showFeedback: false);
    });

    socket!.onConnectError((data) {
      debugPrint('Socket connect error: $data');
      if (mounted) setState(() => socketConnected = false);
    });

    socket!.onError((data) {
      debugPrint('Socket error: $data');
    });

    socket!.onDisconnect((_) {
      debugPrint('DChat disconnected');

      if (mounted) setState(() => socketConnected = false);
    });

    socket!.on('presence:update', (_) {
      refreshUsers(showFeedback: false);
    });

    // The server broadcasts the full user list whenever accounts or presence
    // change. Apply that payload immediately instead of relying only on a GET.
    socket!.on('users:update', handleUsersUpdate);

    socket!.on('message:new', handleIncomingMessage);

    socket!.connect();
  }

  void handleUsersUpdate(dynamic payload) {
    if (payload is! Map || payload['users'] is! List || !mounted) return;

    final updatedUsers = (payload['users'] as List)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) {
          final name = item['username']?.toString().trim() ?? '';
          return name.isNotEmpty && !sameUser(name, username ?? '');
        })
        .toList();

    setState(() {
      users = updatedUsers;
    });
  }

  Future<void> refreshUsers({bool showFeedback = true}) async {
    final authToken = token;
    if (authToken == null || refreshingUsers) return;

    if (mounted) {
      setState(() {
        refreshingUsers = true;
        if (showFeedback) error = '';
      });
    }

    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/users'),
            headers: {'Authorization': 'Bearer $authToken'},
          )
          .timeout(const Duration(seconds: 25));

      final data = decodeResponse(response);

      if (response.statusCode != 200 || data['ok'] != true) {
        throw Exception(data['error']?.toString() ?? 'Could not load users.');
      }

      final rawUsers = data['users'];
      if (rawUsers is! List) {
        throw Exception('The server returned an invalid user list.');
      }

      final loadedUsers = rawUsers
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((item) {
            final name = item['username']?.toString().trim() ?? '';
            return name.isNotEmpty && !sameUser(name, username ?? '');
          })
          .toList();

      if (!mounted) return;

      setState(() {
        users = loadedUsers;
      });

      // Keep the selected conversation if the list refreshes.
      if (selectedUser != null) {
        final stillExists = loadedUsers.any(
          (item) => sameUser(
            item['username']?.toString() ?? '',
            selectedUser!,
          ),
        );

        if (!stillExists) {
          debugPrint(
            'Selected recipient is not in the refreshed user list: '
            '$selectedUser',
          );
        }
      }

      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Loaded ${loadedUsers.length} other user(s).'),
          ),
        );
      }
    } catch (e) {
      debugPrint('Refresh users error: $e');

      if (mounted && showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Refresh failed: ${errorText(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => refreshingUsers = false);
    }
  }

  Future<void> openConversation(String otherUsername) async {
    final other = otherUsername.trim();

    if (other.isEmpty || sameUser(other, username ?? '')) return;

    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      selectedUser = other;
      messages = [];
      loadingMessages = true;
    });

    await loadMessages(other);
  }

  Future<void> loadMessages(String otherUsername) async {
    final authToken = token;

    if (authToken == null) {
      if (mounted) setState(() => loadingMessages = false);
      return;
    }

    try {
      final response = await http
          .get(
            Uri.parse(
              '$baseUrl/api/messages/'
              '${Uri.encodeComponent(otherUsername)}',
            ),
            headers: {'Authorization': 'Bearer $authToken'},
          )
          .timeout(const Duration(seconds: 25));

      final data = decodeResponse(response);

      if (response.statusCode != 200 || data['ok'] != true) {
        throw Exception(
          data['error']?.toString() ?? 'Could not load messages.',
        );
      }

      final rawMessages = data['messages'];
      if (rawMessages is! List) {
        throw Exception('The server returned an invalid message history.');
      }

      final loaded = rawMessages
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      if (!mounted || selectedUser != otherUsername) return;

      setState(() => messages = loaded);
      scrollToLatest();
    } catch (e) {
      debugPrint('Load messages error: $e');

      if (mounted && selectedUser == otherUsername) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load messages: ${errorText(e)}')),
        );
      }
    } finally {
      if (mounted && selectedUser == otherUsername) {
        setState(() => loadingMessages = false);
      }
    }
  }

  void handleIncomingMessage(dynamic data) {
    if (data is! Map) return;

    Map<String, dynamic> incoming;
    try {
      incoming = Map<String, dynamic>.from(data);
    } catch (_) {
      return;
    }

    if (incoming['message'] is Map) {
      incoming = Map<String, dynamic>.from(incoming['message'] as Map);
    }

    final sender = (
      incoming['from'] ??
      incoming['sender'] ??
      incoming['username'] ??
      ''
    ).toString();

    final recipient = (
      incoming['to'] ??
      incoming['recipient'] ??
      incoming['receiver'] ??
      ''
    ).toString();

    final me = username ?? '';
    final other = selectedUser ?? '';

    final isIncomingForMe = sender.isNotEmpty &&
        recipient.isNotEmpty &&
        sameUser(recipient, me) &&
        !sameUser(sender, me);
    final conversationIsOpen = other.isNotEmpty && sameUser(sender, other);
    if (defaultTargetPlatform == TargetPlatform.windows &&
        isIncomingForMe &&
        !conversationIsOpen) {
      final notificationBody = (
        incoming['text'] ?? incoming['content'] ?? 'New message'
      ).toString();
      NotificationService.instance.showMessageNotification(
        title: sender,
        body: notificationBody,
        payload: sender,
      );
    }

    if (other.isNotEmpty &&
        ((sameUser(sender, other) && sameUser(recipient, me)) ||
            (sameUser(sender, me) && sameUser(recipient, other)))) {
      addMessageToChat(incoming);
    }

    refreshUsers(showFeedback: false);
  }

  void addMessageToChat(Map<String, dynamic> message) {
    if (!mounted) return;

    final id = message['id'] ?? message['_id'];

    if (id != null &&
        messages.any((item) => (item['id'] ?? item['_id']) == id)) {
      return;
    }

    setState(() => messages = [...messages, message]);
    scrollToLatest();
  }

  void scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !messageScrollController.hasClients) return;

      messageScrollController.animateTo(
        messageScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> sendMessage() async {
    final text = messageController.text.trim();
    final recipient = selectedUser?.trim();
    final activeSocket = socket;

    if (text.isEmpty || sendingMessage) return;

    if (recipient == null ||
        recipient.isEmpty ||
        sameUser(recipient, username ?? '')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a valid recipient from the user list.'),
        ),
      );
      return;
    }

    if (activeSocket == null || !activeSocket.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connecting to the chat server. Please try again.'),
        ),
      );
      return;
    }

    setState(() => sendingMessage = true);

    debugPrint(
      'DChat send attempt: sender=$username, recipient=$recipient',
    );

    var acknowledged = false;

    try {
      activeSocket.emitWithAck(
        'message:send',
        {
          'to': recipient,
          'recipient': recipient,
          'recipientUsername': recipient,
          'receiverUsername': recipient,
          'targetUsername': recipient,
          'text': text,
          'content': text,
        },
        ack: (dynamic response) {
          if (!mounted || acknowledged) return;
          acknowledged = true;

          if (response is Map && response['ok'] == true) {
            messageController.clear();

            final returnedMessage = response['message'];

            if (returnedMessage is Map) {
              addMessageToChat(
                Map<String, dynamic>.from(returnedMessage),
              );
            } else {
              addMessageToChat({
                'from': username,
                'to': recipient,
                'text': text,
                'createdAt': DateTime.now().toIso8601String(),
              });
            }

            refreshUsers(showFeedback: false);
          } else {
            final reason = response is Map
                ? response['error']?.toString() ??
                    'The server rejected the message.'
                : 'Invalid server acknowledgement: $response';

            debugPrint('DChat send rejected: $response');

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(reason)),
            );
          }

          setState(() => sendingMessage = false);
        },
      );

      // Don't leave the send button spinning forever if the server
      // never acknowledges the event.
      await Future<void>.delayed(const Duration(seconds: 15));

      if (!mounted || acknowledged) return;

      acknowledged = true;
      setState(() => sendingMessage = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The server did not acknowledge the message. '
            'Check the backend connection.',
          ),
        ),
      );
    } catch (e) {
      debugPrint('DChat send exception: $e');

      if (mounted && !acknowledged) {
        acknowledged = true;
        setState(() => sendingMessage = false);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Send failed: ${errorText(e)}')),
        );
      }
    }
  }

  Future<void> logout() async {
    final oldToken = token;
    await NotificationService.instance.setAuthToken(null);
    if (oldToken != null && oldToken.isNotEmpty) {
      await NotificationService.instance.unregisterCurrentFcmToken(oldToken);
    }

    socket?.disconnect();
    socket?.dispose();
    socket = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('dchat_token');
    await prefs.remove('dchat_username');

    if (!mounted) return;

    setState(() {
      token = null;
      username = null;
      selectedUser = null;
      users = [];
      messages = [];
      socketConnected = false;
      error = '';
      passwordController.clear();
      messageController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (token == null || username == null) return buildAuthScreen();
    return buildChatScreen();
  }

  Widget buildAuthScreen() {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.forum_rounded,
                  size: 76,
                  color: Color(0xFF9B93FF),
                ),
                const SizedBox(height: 18),
                const Text(
                  'DChat',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isRegister ? 'Create your account' : 'Welcome back',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: usernameController,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  onSubmitted: (_) {
                    if (!busy) authenticate();
                  },
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                if (error.isNotEmpty) ...[
                  const SizedBox(height: 14),                  Text(
                    error,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: busy ? null : authenticate,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : Text(isRegister ? 'Create account' : 'Log in'),
                  ),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () {
                          setState(() {
                            isRegister = !isRegister;
                            error = '';
                          });
                        },
                  child: Text(
                    isRegister
                        ? 'Already registered? Log in'
                        : 'New to DChat? Create an account',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildChatScreen() {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.forum_rounded, color: Color(0xFF9B93FF)),
            SizedBox(width: 10),
            Text('DChat', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Tooltip(
              message: socketConnected ? 'Connected' : 'Disconnected',
              child: Icon(
                Icons.circle,
                size: 10,
                color: socketConnected ? Colors.greenAccent : Colors.redAccent,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Refresh users',
            onPressed: refreshingUsers ? null : () => refreshUsers(),
            icon: refreshingUsers
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: 'DChat menu',
            onSelected: (value) {
              if (value == 'about') showAppInfo();
              if (value == 'updates') checkForUpdates();
              if (value == 'release_notes') openExternalUrl(githubReleasesUrl);
              if (value == 'repository') openExternalUrl(githubRepositoryUrl);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'about',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.info_outline),
                  title: Text('App information'),
                ),
              ),
              PopupMenuItem(
                value: 'updates',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.system_update_alt),
                  title: Text('Check for updates'),
                ),
              ),
              PopupMenuItem(
                value: 'release_notes',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.notes),
                  title: Text('Release notes'),
                ),
              ),
              PopupMenuItem(
                value: 'repository',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.code),
                  title: Text('GitHub repository'),
                ),
              ),
            ],
            icon: const Icon(Icons.more_vert),
          ),
          IconButton(
            tooltip: 'Log out',
            onPressed: logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 650) {
            return Row(
              children: [
                SizedBox(width: 270, child: buildUserList()),
                const VerticalDivider(width: 1),
                Expanded(child: buildConversation()),
              ],
            );
          }

          if (selectedUser == null) return buildUserList();
          return buildConversation(mobile: true);
        },
      ),
    );
  }

  Widget buildUserList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'CHATS',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Signed in as $username',
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
              const SizedBox(height: 6),
              Text(
                '${users.length} other user(s)',
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: users.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.people_outline,
                          size: 48,
                          color: Colors.white38,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No other users found',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Create another account, then refresh the user list.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white54,
                          ),
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed: refreshingUsers
                              ? null
                              : () => refreshUsers(),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh users'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: users.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 70),
                  itemBuilder: (context, index) {
                    final item = users[index];
                    final name =
                        item['username']?.toString().trim() ?? '';

                    if (name.isEmpty) return const SizedBox.shrink();

                    final online = item['online'] == true ||
                        item['isOnline'] == true;

                    return ListTile(
                      selected: selectedUser == name,
                      selectedTileColor: const Color(0xFF29263F),
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF35314F),
                        child: Text(
                          name[0].toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xFFCEC9FF),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 8,
                            color: online
                                ? Colors.greenAccent
                                : Colors.white30,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            online ? 'Online' : 'Available',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                      onTap: () => openConversation(name),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget buildConversation({bool mobile = false}) {
    final other = selectedUser;

    if (other == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 72, color: Colors.white24),
            SizedBox(height: 16),
            Text(
              'Welcome to DChat',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Select a user to start chatting.',
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFF171721),
            border: Border(
              bottom: BorderSide(color: Color(0xFF292936)),
            ),
          ),
          child: Row(
            children: [
              if (mobile)
                IconButton(
                  tooltip: 'Back to users',
                  onPressed: () {
                    setState(() {
                      selectedUser = null;
                      messages = [];
                    });
                  },
                  icon: const Icon(Icons.arrow_back),
                ),
              CircleAvatar(
                backgroundColor: const Color(0xFF35314F),
                child: Text(
                  other[0].toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFFCEC9FF),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      other,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      socketConnected
                          ? 'Private conversation'
                          : 'Reconnecting...',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Reload messages',
                onPressed: loadingMessages ? null : () => loadMessages(other),
                icon: const Icon(Icons.sync),
              ),
            ],
          ),
        ),
        Expanded(
          child: loadingMessages && messages.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : messages.isEmpty
                  ? const Center(
                      child: Text(
                        'No messages yet. Say hello!',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : ListView.builder(
                      controller: messageScrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];

                        final sender = (
                          message['from'] ??
                          message['sender'] ??
                          message['username'] ??
                          ''
                        ).toString();

                        final mine = sameUser(sender, username ?? '');

                        final body = (
                          message['text'] ??
                          message['content'] ??
                          ''
                        ).toString();

                        final time =
                            message['createdAt'] ?? message['timestamp'];

                        return Align(
                          alignment: mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 440),
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: mine
                                  ? const Color(0xFF51488B)
                                  : const Color(0xFF252531),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft: Radius.circular(mine ? 16 : 4),
                                bottomRight: Radius.circular(mine ? 4 : 16),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(body),
                                ),
                                if (time != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    formatTime(time),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.white60,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: const BoxDecoration(
            color: Color(0xFF171721),
            border: Border(
              top: BorderSide(color: Color(0xFF292936)),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: messageController,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => sendMessage(),
                  decoration: InputDecoration(
                    hintText: 'Message $other...',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    suffixIcon: IconButton(
                      tooltip: 'Clear message',
                      onPressed: () => messageController.clear(),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 48,
                width: 48,
                child: FilledButton(
                  onPressed: sendingMessage ? null : sendMessage,
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: sendingMessage
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String formatTime(dynamic value) {
    try {
      final date = DateTime.parse(value.toString()).toLocal();
      final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
      final minute = date.minute.toString().padLeft(2, '0');
      final period = date.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $period';
    } catch (_) {
      return '';
    }
  }
}