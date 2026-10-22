import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// 应用内自动更新：从 GitHub Releases 检查/多线路下载/唤起安装
class Updater {
  static const _api =
      'https://api.github.com/repos/MrJingLiguo/phone-gps/releases/latest';

  /// 下载加速线路：直连 + 国内镜像前缀（按实测速度自动选优，失败逐路降级）
  static const List<String> _mirrorPrefixes = [
    '',
    'https://ghfast.top/',
    'https://gh-proxy.com/',
    'https://github.moeyy.xyz/',
    'https://gh.llkk.cc/',
    'https://mirror.ghproxy.com/',
  ];

  static Future<UpdateInfo?> check() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final req = await client.getUrl(Uri.parse(_api));
      final resp = await req.close();
      if (resp.statusCode != 200) return null;
      final j =
          jsonDecode(await resp.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      final tag = (j['tag_name'] ?? '') as String;
      final latest = tag.startsWith('v') ? tag.substring(1) : tag;
      if (latest.isEmpty) return null;
      String apkUrl = '';
      for (final a in (j['assets'] as List? ?? [])) {
        if ((a['name'] as String).toLowerCase().endsWith('.apk')) {
          apkUrl = (a['browser_download_url'] as String);
          break;
        }
      }
      if (apkUrl.isEmpty) return null;
      final info = await PackageInfo.fromPlatform();
      if (!_isNewer(latest, info.version)) return null;
      return UpdateInfo(
        current: info.version,
        latest: latest,
        apkUrl: apkUrl,
        notes: (j['body'] ?? '') as String,
      );
    } catch (_) {
      return null;
    }
  }

  /// 语义化版本比较：a > b 才返回 true
  static bool _isNewer(String a, String b) {
    List<int> parse(String s) => s
        .split(RegExp(r'[+\-]'))
        .first
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    final pa = parse(a);
    final pb = parse(b);
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (int i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  /// 并行探测各线路首字节延迟，按快→慢排序返回完整 URL 列表
  static Future<List<String>> _rankUrls(String direct) async {
    Future<(String, double)> probe(String prefix) async {
      final client = HttpClient();
      try {
        client.connectionTimeout = const Duration(seconds: 6);
        final sw = Stopwatch()..start();
        final req = await client.getUrl(Uri.parse('$prefix$direct'));
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
        final resp =
            await req.close().timeout(const Duration(seconds: 6));
        final code = resp.statusCode;
        await resp.drain<void>().timeout(const Duration(seconds: 6));
        if (code == 200 || code == 206) {
          return (prefix, sw.elapsedMilliseconds.toDouble());
        }
        return (prefix, double.infinity);
      } catch (_) {
        return (prefix, double.infinity);
      } finally {
        client.close(force: true);
      }
    }

    final rs = await Future.wait(_mirrorPrefixes.map(probe));
    final ok = rs.where((r) => r.$2 < double.infinity).toList()
      ..sort((a, b) => a.$2.compareTo(b.$2));
    final ranked = [for (final r in ok) '${r.$1}$direct'];
    // 全部失败时至少尝试直连
    if (ranked.isEmpty) ranked.add(direct);
    return ranked;
  }

  /// 多线路下载（自动选最快，失败自动换线），onProgress 0~1
  static Future<String> download(UpdateInfo info,
      {void Function(double)? onProgress}) async {
    final urls = await _rankUrls(info.apkUrl);
    Object? lastErr;
    for (final u in urls) {
      try {
        return await _downloadSingle(u, onProgress: onProgress);
      } catch (e) {
        lastErr = e;
        onProgress?.call(0); // 重置进度
      }
    }
    throw '所有线路下载失败：$lastErr';
  }

  static Future<String> _downloadSingle(String url,
      {void Function(double)? onProgress}) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/fieldmap_update.apk');
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close().timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        throw 'HTTP ${resp.statusCode}';
      }
      final total = resp.contentLength ?? 0;
      final sink = f.openWrite();
      int done = 0;
      try {
        await for (final chunk in resp) {
          done += chunk.length;
          if (total > 0) onProgress?.call(done / total);
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }
      return f.path;
    } finally {
      client.close(force: true);
    }
  }

  /// 后台下载：系统 WorkManager 执行，通知栏显示进度，可切出 app；完成点通知即可安装
  static Future<void> enqueueBackground(UpdateInfo info) async {
    final urls = await _rankUrls(info.apkUrl);
    final dir = await getApplicationDocumentsDirectory();
    final updates = Directory('${dir.path}/updates');
    if (!updates.existsSync()) updates.createSync(recursive: true);
    await FlutterDownloader.enqueue(
      url: urls.first,
      savedDir: updates.path,
      fileName: 'fieldmap_v${info.latest}.apk',
      showNotification: true,
      openFileFromNotification: true,
    );
  }

  /// 唤起系统安装器
  static Future<void> install(String path) async {
    await OpenFilex.open(path,
        type: 'application/vnd.android.package-archive');
  }

  /// 检查并弹出更新对话框（自动+手动共用），有更新返回 true
  static Future<bool> checkAndPrompt(BuildContext context,
      {bool silent = false}) async {
    final u = await check();
    if (u == null) {
      if (!silent && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已是最新版本，或网络不可用')));
      }
      return false;
    }
    if (!context.mounted) return false;
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _UpdateDialog(info: u),
    );
    return true;
  }
}

class UpdateInfo {
  final String current;
  final String latest;
  final String apkUrl;
  final String notes;
  UpdateInfo(
      {required this.current,
      required this.latest,
      required this.apkUrl,
      required this.notes});
}

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  const _UpdateDialog({required this.info});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double _progress = 0;
  bool _downloading = false;
  String? _error;

  Future<void> _start() async {
    setState(() {
      _downloading = true;
      _error = null;
    });
    try {
      final path = await Updater.download(widget.info, onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      await Updater.install(path);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _startBackground() async {
    try {
      await Updater.enqueueBackground(widget.info);
    } catch (_) {
      // 失败时提示走前台下载
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('后台下载启动失败，请用「下载安装」')));
      }
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('已在后台下载（通知栏显示进度），完成后点通知即可安装，可切去其他应用'),
        duration: Duration(seconds: 4)));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('发现新版本 v${widget.info.latest}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('当前版本 v${widget.info.current}',
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          if (widget.info.notes.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 120),
              child: SingleChildScrollView(
                child: Text(widget.info.notes,
                    style: const TextStyle(fontSize: 13)),
              ),
            ),
          const SizedBox(height: 12),
          if (_downloading)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 4),
                Text('${(_progress * 100).toStringAsFixed(0)}%'
                    '（自动选择最快线路）',
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
          if (_error != null)
            Text('下载失败：$_error\n可换「后台下载」或到 GitHub Releases 页手动下载',
                style: const TextStyle(fontSize: 12, color: Colors.red)),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('稍后')),
        OutlinedButton.icon(
          icon: const Icon(Icons.cloud_download, size: 18),
          label: const Text('后台下载'),
          onPressed: _downloading ? null : _startBackground,
        ),
        FilledButton.icon(
          icon: const Icon(Icons.download, size: 18),
          label: const Text('下载安装'),
          onPressed: _downloading ? null : _start,
        ),
      ],
    );
  }
}
