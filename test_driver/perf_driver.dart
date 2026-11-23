import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// Écrit le rapport de integration_test/perf_test.dart dans build/perf/.
Future<void> main() => integrationDriver(
      responseDataCallback: (data) async {
        if (data == null) return;
        final file = File('build/perf/perf_report_${DateTime.now().millisecondsSinceEpoch}.json')..createSync(recursive: true);
        file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
        stdout.writeln('Rapport : ${file.path}');
      },
    );
