import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../services/backup.dart';

/// 更多：数据统计、备份导出、恢复导入
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  Future<void> _export(BuildContext context, bool full) async {
    final app = context.read<AppState>();
    try {
      final path =
          full ? await Backup.exportZip(app) : await Backup.exportJson(app);
      await Backup.shareExport(
        path,
        full ? '地块管家完整备份（含照片），发到新手机上用「导入」恢复' : '地块管家数据备份（不含照片）',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导出失败：$e')));
      }
    }
  }

  Future<void> _import(BuildContext context) async {
    final app = context.read<AppState>();
    final b = await Backup.pickAndParse();
    if (b == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未选择文件或文件不是有效的备份')));
      }
      return;
    }
    if (!context.mounted) return;
    final inP = (b.data['parcels'] as List? ?? []).length;
    final inT = (b.data['tracks'] as List? ?? []).length;
    final inPl = (b.data['places'] as List? ?? []).length;
    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择导入方式'),
        content: Text(
            '备份里有：地块 $inP · 地点 $inPl · 轨迹 $inT\n\n'
            '合并导入：与现有数据按编号去重合并，安全\n'
            '覆盖导入：清空现有数据后恢复备份（照片也会被替换）'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'merge'),
              child: const Text('合并导入')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, 'replace'),
              child: const Text('覆盖导入')),
        ],
      ),
    );
    if (mode == null || !context.mounted) return;
    try {
      final summary = await Backup.apply(app, b,
          replace: mode == 'replace');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导入完成：$summary')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导入失败：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final photoCount = {
      for (final p in app.parcels) ...p.photos,
      for (final p in app.places) ...p.photos,
    }.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('更多'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // 数据统计
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _Stat('地块', '${app.parcels.length}', Icons.grass),
                  _Stat('地点', '${app.places.length}', Icons.place),
                  _Stat('轨迹', '${app.tracks.length}', Icons.route),
                  _Stat('照片', '$photoCount', Icons.photo),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text('备份与恢复',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.backup, color: Colors.green),
                  title: const Text('导出完整备份'),
                  subtitle: const Text('ZIP 包含数据+全部照片，换手机推荐'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _export(context, true),
                ),
                const Divider(height: 1),
                ListTile(
                  leading:
                      const Icon(Icons.data_object, color: Colors.blueGrey),
                  title: const Text('导出数据(JSON)'),
                  subtitle: const Text('仅数据不含照片，体积小'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _export(context, false),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.restore, color: Colors.orange),
                  title: const Text('从备份文件导入'),
                  subtitle: const Text('支持本应用导出的 ZIP 或 JSON'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _import(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              '地块管家 v1.1 · 数据仅存本机\n建议定期导出备份到微信/网盘',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _Stat(this.label, this.value, this.icon);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 4),
        Text(value,
            style:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}
