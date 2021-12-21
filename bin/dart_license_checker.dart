import 'dart:convert';
import 'dart:io';

import 'package:barbecue/barbecue.dart';
import 'package:pana/pana.dart';
import 'package:pana/src/license.dart';
import 'package:path/path.dart';
import 'package:tint/tint.dart';

void main(List<String> arguments) async {
  final urlChecker = UrlChecker();
  final showTransitiveDependencies =
      arguments.contains('--show-transitive-dependencies');
  final checkPathDependencies = arguments.contains('--check-path-dependencies');
  final pubspecFile = File('pubspec.yaml');

  if (!pubspecFile.existsSync()) {
    stderr.writeln('pubspec.yaml file not found in current directory'.red());
    exit(1);
  }

  final pubspec = Pubspec.parseYaml(pubspecFile.readAsStringSync());

  final packageConfigFile = File('.dart_tool/package_config.json');

  if (!pubspecFile.existsSync()) {
    stderr.writeln(
        '.dart_tool/package_config.json file not found in current directory. You may need to run "flutter pub get" or "pub get"'
            .red());
    exit(1);
  }

  print('Checking dependencies...'.blue());

  final packageConfig = json.decode(packageConfigFile.readAsStringSync());

  final rows = <Row>[];

  for (final package in packageConfig['packages']) {
    final name = package['name'];

    if (!showTransitiveDependencies) {
      if (!pubspec.dependencies.containsKey(name)) {
        continue;
      }
    }

    final license = await extractLicense(
      urlChecker: urlChecker,
      packageName: name,
      packageUri: Uri.parse(package['rootUri']),
    );

    if (license.isPathDependency && !checkPathDependencies) {
      print('Skipping local dependency ${license.dependencyName}'.gray());
      continue;
    }

    rows.add(
      Row(
        cells: [
          Cell(
            license.dependencyName,
            style: CellStyle(
              alignment: TextAlignment.TopRight,
            ),
          ),
          Cell(license.licenseName),
          Cell(license.licenseUrl),
        ],
      ),
    );
  }
  print(
    Table(
      tableStyle: TableStyle(border: true),
      header: TableSection(
        rows: [
          Row(
            cells: [
              Cell(
                'Package Name'.bold(),
                style: CellStyle(alignment: TextAlignment.TopRight),
              ),
              Cell('License'.bold()),
              Cell('URL'.bold()),
            ],
            cellStyle: CellStyle(borderBottom: true),
          ),
        ],
      ),
      body: TableSection(
        cellStyle: CellStyle(paddingRight: 2),
        rows: rows,
      ),
    ).render(),
  );
  exit(0);
}

Future<DependencyLicenseInfo> extractLicense({
  required UrlChecker urlChecker,
  required String packageName,
  required packageUri,
}) async {
  var isPathDependency = false;
  if (!packageUri.isScheme('file')) {
    isPathDependency = true;
  }
  final packageRootPath = packageUri.toFilePath();

  var license = await detectLicenseInDir(packageRootPath);
  Pubspec? pubspecData;
  final pubspecFile = File(join(packageRootPath, 'pubspec.yaml'));
  if (pubspecFile.existsSync()) {
    final content = utf8.decode(
      await pubspecFile.readAsBytes(),
      allowMalformed: true,
    );
    pubspecData = Pubspec.parseYaml(content);
  }

  if (pubspecData != null) {
    license = license?.change(
      url: await getLicenseUrl(
        urlChecker,
        pubspecData.repository ?? pubspecData.homepage,
        license,
      ),
    );
  }
  return DependencyLicenseInfo(
    dependencyName: packageName,
    isPathDependency: isPathDependency,
    license: license,
  );
}

class DependencyLicenseInfo {
  DependencyLicenseInfo({
    required this.dependencyName,
    required this.isPathDependency,
    required this.license,
  });

  final String dependencyName;
  final bool isPathDependency;
  final LicenseFile? license;

  String get licenseName => license?.name ?? 'N/A';

  String get licenseUrl => license?.url ?? 'N/A';
}
