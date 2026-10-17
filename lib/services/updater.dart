import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// 应用内自动更新：从 GitHub Releases 检查/下载/唤起安装
class Updater {
  static const _api =
      'https://api.github.com/repos/MrJingLiguo/phone-gps/releases/latest';

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

  /// 下载 APK 到临时目录，onProgress 回调 0~1
  static Future<String> download(String url,
      {void Function(double)? onProgress}) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/fieldmap_update.apk');
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(url));
    final resp = await req.close();
    if (resp.statusCode != 200) {
      throw '下载失败 HTTP ${resp.statusCode}';
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
      client.close();
    }
    return f.path;
  }

  /// 唤起系统安装器
  static Future<void> install(String path) async {
    await OpenFilex.open(path,
        fileType: 'application/vnd.android.package-archive');
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
      final path = await Updater.download(widget.info.apkUrl,
          onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      await Updater.install(path);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() {
        _downloading = false;
        _error = '$e';
      });
    }
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
                Text('${(_progress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
          if (_error != null)
            Text('下载失败：$_error\n可到 GitHub Releases 页手动下载',
                style: const TextStyle(fontSize: 12, color: Colors.red)),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('以后再说')),
        if (!_downloading)
          FilledButton.icon(
            icon: const Icon(Icons.download),
            label: const Text('下载并安装'),
            onPressed: _start,
          ),
      ],
    );
  }
}
