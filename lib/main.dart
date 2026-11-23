import 'package:material_ui/material_ui.dart';

import 'app/app.dart';
import 'core/errors.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppError.install();
  runApp(const LireoApp());
}
