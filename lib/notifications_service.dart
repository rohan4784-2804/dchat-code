import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import 'firebase_options.dart';

const String _dchatBaseUrl = 'https://dchat-pjz5.onrender.com';
const AndroidNotificationChannel _messageChannel = AndroidNotificationChannel(
  'dchat_messages',
  'DChat messages',
  description: 'Notifications for new DChat messages',
  importance: Importance.high,
  playSound: true,
);

@pragma('vm:entry-point')
Future<void> dchatFirebaseBackgroundHandler(RemoteMessage message) async {
  // Android automatically displays FCM messages that contain a notification
  // payload while the app is in the background or terminated.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _firebaseReady = false;
  String? _authToken;
  String? _currentFcmToken;
  bool _refreshListenerAttached = false;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const windowsSettings = WindowsInitializationSettings(
      appName: 'DChat',
      appUserModelId: 'com.rohan.dchat',
      guid: '8e5f24a4-0d4b-4d1f-9d21-1a3f2a78d0c1',
    );

    final settings = InitializationSettings(
      android: androidSettings,
      windows: windowsSettings,
    );

    await _local.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        debugPrint('DChat notification tapped: ${response.payload ?? ''}');
      },
    );

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        FirebaseMessaging.onBackgroundMessage(
          dchatFirebaseBackgroundHandler,
        );

        final androidPlugin = _local.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        await androidPlugin?.createNotificationChannel(_messageChannel);
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );

        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          final notification = message.notification;
          if (notification == null) return;
          showMessageNotification(
            title: notification.title ?? 'DChat',
            body: notification.body ?? 'You have a new message',
            payload: message.data['sender']?.toString(),
          );
        });
        _firebaseReady = true;
      } catch (e) {
        debugPrint('Firebase notification initialization failed: $e');
      }
    }

    _initialized = true;
  }

  Future<void> setAuthToken(String? authToken) async {
    _authToken = authToken;
    if (!_firebaseReady || authToken == null || authToken.isEmpty) return;

    try {
      final messaging = FirebaseMessaging.instance;
      final fcmToken = await messaging.getToken();
      if (fcmToken != null && fcmToken.isNotEmpty) {
        _currentFcmToken = fcmToken;
        await _registerToken(fcmToken, authToken);
      }

      if (!_refreshListenerAttached) {
        _refreshListenerAttached = true;
        messaging.onTokenRefresh.listen((newToken) async {
          _currentFcmToken = newToken;
          final latestAuthToken = _authToken;
          if (latestAuthToken != null && latestAuthToken.isNotEmpty) {
            await _registerToken(newToken, latestAuthToken);
          }
        });
      }
    } catch (e) {
      debugPrint('Could not register DChat FCM token: $e');
    }
  }

  Future<void> _registerToken(String fcmToken, String authToken) async {
    final response = await http
        .post(
          Uri.parse('$_dchatBaseUrl/api/push-token'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $authToken',
          },
          body: jsonEncode({'token': fcmToken}),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint('FCM token registration failed: HTTP ${response.statusCode}');
    }
  }

  Future<void> unregisterCurrentFcmToken(String authToken) async {
    final fcmToken = _currentFcmToken;
    if (fcmToken == null || fcmToken.isEmpty) return;
    try {
      await http
          .delete(
            Uri.parse('$_dchatBaseUrl/api/push-token'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $authToken',
            },
            body: jsonEncode({'token': fcmToken}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('Could not unregister FCM token: $e');
    }
    _currentFcmToken = null;
  }

  Future<void> showMessageNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized || body.trim().isEmpty) return;

    const androidDetails = AndroidNotificationDetails(
      'dchat_messages',
      'DChat messages',
      channelDescription: 'Notifications for new DChat messages',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    );
    const windowsDetails = WindowsNotificationDetails();

    try {
      await _local.show(
        DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
        title,
        body,
        const NotificationDetails(
          android: androidDetails,
          windows: windowsDetails,
        ),
        payload: payload,
      );
    } catch (e) {
      debugPrint('Could not display local notification: $e');
    }
  }
}