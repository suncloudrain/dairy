import 'package:flutter/material.dart';

import 'app/app_dependencies.dart';
import 'app/dairy_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(DairyApp(initialize: AppDependencies.initialize));
}
