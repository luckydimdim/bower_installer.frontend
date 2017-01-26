import 'dart:io';
import 'dart:async';

import 'package:barback/barback.dart';
import 'package:path/path.dart' as path;
import 'package:grinder/grinder_files.dart' as grinder;
import 'package:crypto/crypto.dart';

/// Installs bower modules in all sub folders
class BowerInstaller extends AggregateTransformer {
  BowerInstaller() {}

  /// Registers transformer
  BowerInstaller.asPlugin();

  /// Provides execution of installer for only 1 time
  classifyPrimary(AssetId id) {
    String mainFilePath = 'web/main.dart';

    if (id.path == mainFilePath)
      return path.url.dirname(id.path);
    else
      return null;
  }

  /// Executes installation
  Future apply(AggregateTransform transform) async {
    String startDirPath = path.join(path.current, '.pub');
    Directory startDir = new Directory(startDirPath);

    List<FileSystemEntity> projectEntityList =
        startDir.listSync(recursive: true, followLinks: false);

    for (FileSystemEntity projectEntity in projectEntityList) {
      // Preserve bower sub modules installation
      if (projectEntity.path.contains('bower_components')) continue;

      if (path.basename(projectEntity.path) != 'bower.json') continue;

      print('projectPath: '+ path.dirname(projectEntity.path));

      String bowerModulesPath =
          path.join(path.dirname(projectEntity.path), 'bower_components');
      Directory bowerModulesDir = new Directory(bowerModulesPath);

      String lockFilePath =
          path.join(path.dirname(projectEntity.path), 'bower.lock');
      var lockFile = new File(lockFilePath);

      Digest bowerDigest =
          await md5.bind((projectEntity as File).openRead()).first;
      String bowerHash = bowerDigest.toString();

      print('bower.json hash is ' + bowerHash);

      if (!(lockFile.existsSync()) ||
          (lockFile.readAsStringSync()) != bowerHash) {
        print(
            'lock file doesn\'t exist or hashes are different, installing...');

        String bowerRcPath =
            path.join(path.dirname(projectEntity.path), '.bowerrc');
        var bowerRcFile = new File(bowerRcPath);

        if (bowerRcFile.existsSync()) {
          print(bowerModulesPath + ' .bowerrc exists, deleting...');

          bowerRcFile.deleteSync();
        }

        print('installing components...');

        String workingDirPath = path.dirname(projectEntity.path);
        Process.runSync('bower', ['install'],
            workingDirectory: workingDirPath, runInShell: true);

        print(bowerModulesPath + ' installed, coping...');

        String destinationModulesPath =
            path.joinAll([path.current, 'web', 'vendor']);
        Directory destinationModulesDir = new Directory(destinationModulesPath);
        grinder.copyDirectory(bowerModulesDir, destinationModulesDir);

        print('copied. creating lock file...');

        print('writing hash to file...');

        new File(lockFilePath)
          ..create()
          ..writeAsString(bowerHash);

        print('lock file created.');

        // Add installed modules to output dir
        List<FileSystemEntity> moduleEntityList =
            bowerModulesDir.listSync(recursive: true, followLinks: false);

        for (FileSystemEntity moduleEntity in moduleEntityList) {
          if (!(moduleEntity is File)) continue;

          String destinationModulePath =
            moduleEntity.path.replaceAll(bowerModulesPath, 'web/vendor');
          destinationModulePath = path.normalize(destinationModulePath);

          var destinationModuleFile = new File(destinationModulePath);
          if ( destinationModuleFile.existsSync() ) continue;

          AssetId outputAssetId =
            new AssetId(transform.package, destinationModulePath);

          Asset outputAsset = new Asset.fromFile(outputAssetId, moduleEntity);

          try {
            transform.addOutput(outputAsset);
          } catch(exception, stackTrace) {
            print(exception);
            print(stackTrace);
          }
        }
        print('module installation done.');
      } else {
        print(bowerModulesPath + ' exists, doing nothing...');
      }
    }
  }
}