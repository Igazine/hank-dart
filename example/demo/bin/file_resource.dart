import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:hank/src/Types.dart';

class FileResource extends Resource {
  static FileResource create(String filePath) {
    return FileResource(p.canonicalize(filePath));
  }

  FileResource(String id) : super(id);

  @override
  Future<void> load() async {
    if (content != null) return;
    content = File(id).readAsStringSync();
  }

  @override
  Resource resolve(String id) {
    String filePath = id;
    if (!p.isAbsolute(filePath)) {
      String baseDir = p.dirname(this.id);
      filePath = p.join(baseDir, id);
    }

    if (p.extension(filePath).isEmpty) {
      if (File('$filePath.hank').existsSync()) {
        filePath = '$filePath.hank';
      }
    }

    return FileResource.create(filePath);
  }
}
