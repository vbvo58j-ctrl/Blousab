import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'screens/communities_screen.dart';
import 'services/bluetooth_classic_service.dart';
import 'services/local_network_service.dart';

const String supportUrl = 'https://wsend.co/967737414884';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BlousabApp());
}

class BlousabApp extends StatelessWidget {
  const BlousabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'بلوساب',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF075E54)),
        useMaterial3: true,
        fontFamily: 'sans-serif',
        appBarTheme: const AppBarTheme(centerTitle: false),
      ),
      home: const BluetoothGate(),
    );
  }
}

class BluetoothGate extends StatefulWidget {
  const BluetoothGate({super.key});

  @override
  State<BluetoothGate> createState() => _BluetoothGateState();
}

class _BluetoothGateState extends State<BluetoothGate> {
  final BluetoothClassicService _bluetooth = BluetoothClassicService.instance;
  bool _checking = true;
  bool _supported = false;
  bool _enabled = false;
  bool _busy = false;
  String _status = 'جارٍ التحقق من البلوتوث…';

  @override
  void initState() {
    super.initState();
    _checkBluetooth();
  }

  Future<void> _checkBluetooth() async {
    if (mounted) setState(() { _checking = true; });
    try {
      final supported = await _bluetooth.isSupported();
      if (!supported) {
        if (mounted) setState(() {
          _supported = false;
          _enabled = false;
          _status = 'هذا الهاتف لا يدعم Bluetooth Classic.';
          _checking = false;
        });
        return;
      }
      final permissions = await _bluetooth.requestPermissions();
      if (!permissions) {
        if (mounted) setState(() {
          _supported = true;
          _enabled = false;
          _status = 'يلزم السماح بصلاحيات البلوتوث للمتابعة.';
          _checking = false;
        });
        return;
      }
      final enabled = await _bluetooth.isEnabled();
      if (!mounted) return;
      setState(() {
        _supported = true;
        _enabled = enabled;
        _status = enabled
            ? 'البلوتوث جاهز. يمكنك فتح بلوساب.'
            : 'شغّل البلوتوث للمتابعة إلى التطبيق.';
        _checking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'تعذر التحقق من البلوتوث. تحقق من الصلاحيات ثم أعد المحاولة.';
        _checking = false;
      });
    }
  }

  Future<void> _enableBluetooth() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!await _bluetooth.requestPermissions()) {
        _notice('لم تُمنح صلاحيات البلوتوث.');
        return;
      }
      if (!await _bluetooth.isEnabled()) {
        await _bluetooth.requestEnable();
        _notice('وافق على تشغيل البلوتوث في نافذة Android، ثم اضغط «إعادة التحقق».');
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _checkBluetooth();
    } catch (e) {
      _notice('تعذر تشغيل البلوتوث: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_supported && _enabled) return const BlousabShell();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Icon(Icons.bluetooth, size: 54,
                      color: Theme.of(context).colorScheme.onPrimaryContainer),
                  ),
                  const SizedBox(height: 24),
                  Text('بلوساب', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  const Text('تواصل محلي عبر Bluetooth Classic', textAlign: TextAlign.center),
                  const SizedBox(height: 18),
                  Text(_status, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  if (_checking || _busy) const CircularProgressIndicator(),
                  if (!_checking && !_enabled) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _supported ? _enableBluetooth : null,
                        icon: const Icon(Icons.bluetooth_searching),
                        label: const Text('تشغيل البلوتوث'),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _checkBluetooth,
                      child: const Text('إعادة التحقق'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'لن تظهر واجهة المحادثات حتى يتم تفعيل البلوتوث.',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BlousabShell extends StatefulWidget {
  const BlousabShell({super.key});

  @override
  State<BlousabShell> createState() => _BlousabShellState();
}

class _BlousabShellState extends State<BlousabShell> {
  String _userName = 'مستخدم بلوساب';
  String _background = 'افتراضي';
  bool _lanEnabled = true;
  String _about = 'متاح للتواصل';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _startBluetoothListener();
  }

  Future<void> _startBluetoothListener() async {
    try {
      await BluetoothClassicService.instance.startServer();
    } catch (_) {
      // The user can start listening from the Bluetooth action if Android
      // has just returned from the system permission/enable dialog.
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _userName = prefs.getString('wasl_user_name') ?? 'مستخدم بلوساب';
      _background = prefs.getString('wasl_background') ?? 'افتراضي';
      _lanEnabled = prefs.getBool('blousab_lan_enabled') ?? true;
      _about = prefs.getString('blousab_user_about') ?? 'متاح للتواصل';
    });
  }

  Future<void> _openSettings() async {
    final nameController = TextEditingController(text: _userName);
    final aboutController = TextEditingController(text: _about);
    String selectedBackground = _background;
    bool selectedLan = _lanEnabled;
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('الإعدادات'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: Color(0xFF075E54),
                      child: Icon(Icons.person, color: Colors.white),
                    ),
                    title: Text('الحساب الشخصي'),
                    subtitle: Text('الاسم والصورة التعريفية'),
                  ),
                  TextField(
                    controller: nameController,
                    maxLength: 40,
                    decoration: const InputDecoration(
                      labelText: 'اسم المستخدم',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  TextField(
                    controller: aboutController,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'النبذة',
                      prefixIcon: Icon(Icons.info_outline),
                    ),
                  ),
                  const Divider(),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.palette_outlined),
                    title: Text('المظهر'),
                    subtitle: Text('تخصيص ألوان التطبيق'),
                  ),
                  DropdownButtonFormField<String>(
                    value: selectedBackground,
                    decoration: const InputDecoration(labelText: 'سمة التطبيق'),
                    items: const [
                      DropdownMenuItem(value: 'افتراضي', child: Text('أخضر واتساب')),
                      DropdownMenuItem(value: 'فاتح', child: Text('فاتح')),
                      DropdownMenuItem(value: 'داكن', child: Text('داكن')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => selectedBackground = value);
                      }
                    },
                  ),
                  const Divider(),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.lock_outline),
                    title: Text('الخصوصية'),
                  ),
                  const Padding(
                    padding: EdgeInsetsDirectional.only(start: 12, end: 12, bottom: 12),
                    child: Text(
                      'تُعرض علامة ✓ للرسالة المحفوظة محليًا. تأكيد التسليم والقراءة بين هاتفين يحتاج إلى اتصال وإقرار فعلي من الطرف الآخر.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  const Divider(),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.devices),
                    title: Text('الاتصالات'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: selectedLan,
                    title: const Text('استخدام الشبكة المحلية Wi-Fi'),
                    subtitle: const Text('للأجهزة المتصلة بالشبكة نفسها'),
                    onChanged: (value) => setDialogState(() => selectedLan = value),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'تُحفظ الإعدادات على هذا الهاتف. بعض خيارات الخصوصية تعتمد على دعم الاتصال بين الأجهزة.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, {
                'name': nameController.text.trim(),
                'about': aboutController.text.trim(),
                'background': selectedBackground,
                'lanEnabled': selectedLan,
              }),
              child: const Text('حفظ التغييرات'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    aboutController.dispose();
    if (result == null) return;

    final enteredName = (result['name'] as String? ?? '').trim();
    final cleanName = enteredName.isEmpty ? 'مستخدم بلوساب' : enteredName;
    final about = (result['about'] as String? ?? '').trim();
    final background = result['background'] as String? ?? 'افتراضي';
    final lanEnabled = result['lanEnabled'] as bool? ?? true;
    final prefs2 = await SharedPreferences.getInstance();
    await prefs2.setString('wasl_user_name', cleanName);
    await prefs2.setString('blousab_user_about', about);
    await prefs2.setString('wasl_background', background);
    await prefs2.setBool('blousab_lan_enabled', lanEnabled);
    final userId = (prefs2.getString('wasl_user_id') ?? '').trim();
    if (lanEnabled && userId.isNotEmpty) {
      try {
        await LocalNetworkService.instance.start(userId: userId, userName: cleanName);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذر تشغيل الشبكة المحلية. تحقق من اتصال Wi-Fi.')),
          );
        }
      }
    } else if (!lanEnabled) {
      await LocalNetworkService.instance.stop();
    }
    if (!mounted) return;
    setState(() {
      _userName = cleanName;
      _about = about;
      _background = background;
      _lanEnabled = lanEnabled;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ الإعدادات وتطبيقها.')),
    );
  }

  Future<void> _openSupport() async {
    final uri = Uri.parse(supportUrl);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر فتح رابط دعم واتساب.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر فتح رابط دعم واتساب.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = _background == 'داكن' ? Brightness.dark : Brightness.light;
    return Theme(
      data: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF075E54),
          brightness: brightness,
        ),
        useMaterial3: true,
        fontFamily: 'sans-serif',
      ),
      child: Scaffold(
      appBar: AppBar(
        title: const Text('بلوساب'),
        actions: [
          IconButton(
            tooltip: 'الحساب والإعدادات',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: 'التواصل مع الدعم عبر واتساب',
            onPressed: _openSupport,
            icon: const Icon(Icons.support_agent),
          ),
        ],
      ),
      body: const CommunitiesScreen(),
      floatingActionButton: FloatingActionButton.small(
        tooltip: 'استقبال البلوتوث وإظهار الهاتف للأجهزة القريبة',
        onPressed: () async {
          final service = BluetoothClassicService.instance;
          try {
            final enabled = await service.isEnabled();
            if (!enabled) {
              await service.requestEnable();
            } else {
              await service.startServer();
              await service.requestDiscoverable();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('بدأ استقبال البلوتوث. وافق على جعل الهاتف مرئيًا للأجهزة القريبة لمدة 5 دقائق للانضمام الأول.')),
                );
              }
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('تعذر تشغيل استقبال البلوتوث: $e')),
              );
            }
          }
        },
        child: const Icon(Icons.bluetooth_searching),
      ),
      ),
    );
  }
}