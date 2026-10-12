import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wireguard_flutter/wireguard_flutter.dart';

void main() {
  runApp(const NovaVpnApp());
}

class NovaVpnApp extends StatelessWidget {
  const NovaVpnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NovaVPN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF55AAFF)),
        useMaterial3: true,
      ),
      home: const WebViewScreen(),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  static const String apiUrl = 'https://81.200.152.53/api/vpn/connect';
  static const String apiSecret = 'bSfo9p4sICztBHxAe4f_o1QhWhoEkwwnkyKpVjwH3QI';
  static const String vpnServerAddress = '185.196.117.248';
  static const String vpnInterfaceName = 'novavpn';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF070C14))
      ..addJavaScriptChannel('AndroidBridge', onMessageReceived: _onJsMessage)
      ..loadFlutterAsset('assets/NovaVPN_test.html');
  }

  Future<void> _onJsMessage(JavaScriptMessage message) async {
    try {
      final data = jsonDecode(message.message);
      final action = data['action'] as String?;

      if (action == 'connectVpn') {
        await _handleConnect();
      } else if (action == 'disconnectVpn') {
        await _handleDisconnect();
      } else if (action == 'openBot') {
        _sendToJs('onError', {'message': 'Оплата через Telegram: @Wghalp_bot'});
      } else if (action == 'saveTgId') {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('tg_id', data['tg_id'].toString());
      }
    } catch (e) {
      debugPrint('JS error: $e');
    }
  }

  Future<void> _handleConnect() async {
    final prefs = await SharedPreferences.getInstance();
    final tgId = prefs.getString('tg_id');

    if (tgId == null || tgId.isEmpty) {
      _sendToJs('onError', {'message': 'Введите Telegram ID'});
      return;
    }

    try {
      // 1. Запрос к API — получаем .conf
      final client = io.HttpClient()
        ..badCertificateCallback =
            (io.X509Certificate cert, String host, int port) => true;

      final request = await client.postUrl(Uri.parse(apiUrl));
      request.headers.contentType = io.ContentType.json;
      request.write(jsonEncode({
        'tg_id': int.parse(tgId),
        'secret': apiSecret,
      }));

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode != 200) {
        try {
          final error = jsonDecode(body);
          _sendToJs('onError', {'message': error['detail'] ?? 'Ошибка API'});
        } catch (_) {
          _sendToJs('onError', {'message': 'Ошибка API: ${response.statusCode}'});
        }
        return;
      }

      final data = jsonDecode(body);
      final config = data['config'] as String;
      debugPrint('Config received (${config.length} bytes)');

      // 2. Поднимаем WireGuard
      final wg = WireGuardFlutter.instance;
      await wg.initialize(interfaceName: vpnInterfaceName);
      await wg.startVpn(
        serverAddress: vpnServerAddress,
        wgQuickConfig: config,
        providerBundleIdentifier: '',
      );

      _sendToJs('onConnected', {});
    } catch (e) {
      _sendToJs('onError', {'message': 'Ошибка VPN: $e'});
    }
  }

  Future<void> _handleDisconnect() async {
    try {
      await WireGuardFlutter.instance.stopVpn();
      _sendToJs('onDisconnected', {});
    } catch (e) {
      _sendToJs('onError', {'message': 'Ошибка отключения: $e'});
    }
  }

  void _sendToJs(String function, Map<String, dynamic> data) {
    _controller.runJavaScript('$function(${jsonEncode(data)});');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: WebViewWidget(controller: _controller),
      ),
    );
  }
}