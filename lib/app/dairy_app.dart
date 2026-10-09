import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_dependencies.dart';
import 'app_shell.dart';

class DairyApp extends StatelessWidget {
  const DairyApp({super.key, required this.initialize});
  final Future<AppDependencies> Function() initialize;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '日记与任务',
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF476B62)),
      useMaterial3: true,
    ),
    home: _Bootstrap(initialize: initialize),
  );
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap({required this.initialize});
  final Future<AppDependencies> Function() initialize;

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late Future<AppDependencies> _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = widget.initialize();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AppDependencies>(
    future: _initialization,
    builder: (context, snapshot) {
      if (snapshot.hasData) return AppShell(dependencies: snapshot.requireData);
      if (snapshot.hasError) {
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('无法打开本地数据，请重试。'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => setState(() {
                    _initialization = widget.initialize();
                  }),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        );
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    },
  );
}
