import 'package:flutter/material.dart';
import 'package:movil_architect/core/theme/app_colors.dart';
import 'package:webview_flutter/webview_flutter.dart';

class GoogleAuthView extends StatefulWidget {
  const GoogleAuthView({super.key, required this.startUrl});

  final String startUrl;

  @override
  State<GoogleAuthView> createState() => _GoogleAuthViewState();
}

class _GoogleAuthViewState extends State<GoogleAuthView> {
  late final WebViewController _controller;
  var _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (_handle(request.url)) return NavigationDecision.prevent;
            return NavigationDecision.navigate;
          },
          onUrlChange: (change) {
            final url = change.url;
            if (url != null) _handle(url);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.startUrl));
  }

  bool _handle(String url) {
    if (_finished) return true;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final token = uri.queryParameters['access_token'];
    final error = uri.queryParameters['oauth_error'];
    if (token != null && token.isNotEmpty) {
      _finished = true;
      Navigator.of(context).pop(token);
      return true;
    }
    if (error != null && error.isNotEmpty) {
      _finished = true;
      Navigator.of(context).pop('error:$error');
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Continuar con Google'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        elevation: 0,
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
