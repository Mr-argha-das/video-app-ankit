import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/widgets.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _interests;
  String _gender = 'other';
  XFile? _photo;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user ?? {};
    _name = TextEditingController(text: (user['name'] ?? '').toString());
    final interests = user['interests'];
    _interests = TextEditingController(text: interests is List ? interests.join(', ') : '');
    _gender = (user['gender'] ?? 'other').toString();
  }

  @override
  void dispose() {
    _name.dispose();
    _interests.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      final bytes = _photo != null ? await _photo!.readAsBytes() : null;
      await context.read<AuthProvider>().updateProfile(
            name: _name.text.trim(),
            gender: _gender,
            interestsCsv: _interests.text.trim(),
            photoBytes: bytes,
            photoName: _photo?.name ?? 'photo.jpg',
          );
      if (!mounted) return;
      showSnack(context, '✅ Profile updated!');
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (_) {
      if (mounted) showSnack(context, 'Update failed', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: GestureDetector(
                onTap: () async {
                  final img = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 80);
                  if (img != null) setState(() => _photo = img);
                },
                child: CircleAvatar(
                  radius: 44,
                  backgroundColor: const Color(0xFF252438),
                  backgroundImage: _photo == null && auth.avatarUrl.isNotEmpty ? NetworkImage(auth.avatarUrl) : null,
                  child: _photo != null
                      ? const Icon(Icons.check_circle, color: Colors.green, size: 34)
                      : const Icon(Icons.add_a_photo, color: Colors.white54),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Center(child: Text('Tap to change photo', style: TextStyle(fontSize: 12, color: Colors.white54))),
            const SizedBox(height: 24),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: ['male', 'female', 'other'].contains(_gender) ? _gender : 'other',
              decoration: const InputDecoration(labelText: 'Gender'),
              dropdownColor: const Color(0xFF252438),
              items: const [
                DropdownMenuItem(value: 'male', child: Text('Male')),
                DropdownMenuItem(value: 'female', child: Text('Female')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: (v) => setState(() => _gender = v ?? 'other'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _interests,
              decoration: const InputDecoration(
                labelText: 'Interests (comma separated)',
                hintText: 'Music, Dance, Travel',
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: auth.busy ? null : _save,
              child: auth.busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}
