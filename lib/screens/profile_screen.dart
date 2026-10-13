import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_service.dart';

class ProfileScreen extends StatefulWidget {
  final String username;
  final ValueChanged<String> onUsernameChanged;
  final double textScale;
  final ValueChanged<double> onTextScaleChanged;
  final Color accentColor;
  final ValueChanged<Color> onAccentColorChanged;

  static const double minTextScale = 0.85;
  static const double maxTextScale = 1.3;
  static const double defaultTextScale = 1.0;

  // First entry is the app's default accent (deep purple).
  static const Color defaultAccent = Color(0xFF673AB7);
  static const List<Color> accentOptions = [
    defaultAccent,
    Color(0xFF2196F3), // blue
    Color(0xFF009688), // teal
    Color(0xFF4CAF50), // green
    Color(0xFFFF9800), // orange
    Color(0xFFE91E63), // pink
    Color(0xFFF44336), // red
  ];

  const ProfileScreen({
    super.key,
    required this.username,
    required this.onUsernameChanged,
    required this.textScale,
    required this.onTextScaleChanged,
    required this.accentColor,
    required this.onAccentColorChanged,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const String _avatarPrefKey = 'profileAvatar';

  // The avatars people can choose from. Add or remove emoji here freely; the
  // chosen emoji itself is what gets saved. "Use my initial" is always offered
  // as the first choice on top of these.
  static const List<String> _avatarEmojis = [
    '🐱', '🐶', '🦊', '🐼', '🐨', '🦁',
    '🐸', '🐧', '🦄', '🚀', '🌟',
  ];

  // null = no avatar chosen, so the first letter of the name is shown.
  String? _avatarEmoji;

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  Future<void> _loadAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_avatarPrefKey);
    if (saved == null || !mounted) return;
    setState(() {
      _avatarEmoji = saved;
    });
  }

  Future<void> _selectAvatar(String? emoji) async {
    setState(() {
      _avatarEmoji = emoji;
    });
    final prefs = await SharedPreferences.getInstance();
    if (emoji == null) {
      await prefs.remove(_avatarPrefKey);
    } else {
      await prefs.setString(_avatarPrefKey, emoji);
    }
  }

  String get _initial {
    final name = widget.username.trim();
    if (name.isEmpty) return '?';
    return String.fromCharCode(name.runes.first).toUpperCase();
  }

  // Avatar glyphs use noScaling so they stay the same size when the person
  // changes the app's font size.
  Widget _buildAvatarGlyph({required String? emoji, required double fontSize}) {
    final colors = Theme.of(context).colorScheme;
    return Text(
      emoji ?? _initial,
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        color: colors.onPrimaryContainer,
      ),
    );
  }

  Widget _buildAvatarOption({required String? emoji}) {
    final colors = Theme.of(context).colorScheme;
    final isSelected = emoji == _avatarEmoji;

    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        _selectAvatar(emoji);
      },
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? colors.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: CircleAvatar(
          radius: 26,
          backgroundColor: colors.primaryContainer,
          child: _buildAvatarGlyph(emoji: emoji, fontSize: emoji == null ? 22 : 26),
        ),
      ),
    );
  }

  void _showAvatarPicker() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choose an avatar',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _buildAvatarOption(emoji: null),
                    ..._avatarEmojis.map((emoji) => _buildAvatarOption(emoji: emoji)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _editName() async {
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => _EditNameDialog(initialName: widget.username),
    );
    if (newName == null || newName.isEmpty || newName == widget.username) {
      return;
    }
    widget.onUsernameChanged(newName);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Name updated')),
    );
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You can sign back in anytime with the same email and password.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      // Reminders and timer alerts belong to the account that is leaving. They
      // are scheduled again from that account's own tasks when it signs back in.
      try {
        await NotificationService.instance.cancelAll();
      } catch (_) {
        // Never let this get in the way of signing out.
      }
      await FirebaseAuth.instance.signOut();
      // No navigation here on purpose — main.dart's StreamBuilder detects
      // this automatically and swaps back to the sign-in screen.
    }
  }

  Widget _buildAvatar() {
    final colors = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: _showAvatarPicker,
      child: Stack(
        children: [
          CircleAvatar(
            radius: 44,
            backgroundColor: colors.primaryContainer,
            child: _buildAvatarGlyph(emoji: _avatarEmoji, fontSize: 40),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
              child: Icon(Icons.edit, size: 14, color: colors.onPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        _buildAvatar(),
        const SizedBox(width: 16),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  widget.username,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit, size: 20),
                tooltip: 'Edit name',
                visualDensity: VisualDensity.compact,
                onPressed: _editName,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFontSizeSection() {
    final scale = widget.textScale
        .clamp(ProfileScreen.minTextScale, ProfileScreen.maxTextScale)
        .toDouble();
    final percent = (scale * 100).round();
    final isDefault = percent == (ProfileScreen.defaultTextScale * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Font size', style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('$percent%', style: const TextStyle(color: Colors.grey)),
          ],
        ),
        Row(
          children: [
            const Text('A', style: TextStyle(fontSize: 12)),
            Expanded(
              child: Slider(
                value: scale,
                min: ProfileScreen.minTextScale,
                max: ProfileScreen.maxTextScale,
                divisions: 9, // 5% steps
                label: '$percent%',
                // Round to the nearest 5% so float drift never gets saved.
                onChanged: (value) =>
                    widget.onTextScaleChanged((value * 20).round() / 20),
              ),
            ),
            const Text('A', style: TextStyle(fontSize: 22)),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: isDefault
                ? null
                : () => widget.onTextScaleChanged(ProfileScreen.defaultTextScale),
            child: const Text('Reset'),
          ),
        ),
      ],
    );
  }

  Widget _buildAccentColorSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Accent color', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: ProfileScreen.accentOptions.map((color) {
            final isSelected = color.toARGB32() == widget.accentColor.toARGB32();
            return GestureDetector(
              onTap: () => widget.onAccentColorChanged(color),
              child: CircleAvatar(
                radius: 20,
                backgroundColor: color,
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white)
                    : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildHeader(),
          const Divider(height: 48),
          _buildFontSizeSection(),
          const SizedBox(height: 24),
          _buildAccentColorSection(),
          const Divider(height: 48),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _confirmSignOut,
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Owns its own controller so it is disposed together with the dialog route,
// after the closing animation has finished.
class _EditNameDialog extends StatefulWidget {
  final String initialName;

  const _EditNameDialog({required this.initialName});

  @override
  State<_EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends State<_EditNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit name'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          hintText: 'Enter your name',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}