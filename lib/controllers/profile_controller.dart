import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:movil_architect/core/app_services.dart';
import 'package:movil_architect/core/network/api_exception.dart';
import 'package:movil_architect/models/auth_models.dart';
import 'package:movil_architect/services/auth_service.dart';
import 'package:movil_architect/services/mobile_api_service.dart';

class ProfileController extends ChangeNotifier {
  ProfileController({
    AuthService? authService,
    MobileApiService? mobileApiService,
  })  : _authService = authService ?? AppServices.instance.authService,
        _mobileApiService =
            mobileApiService ?? AppServices.instance.mobileApiService;

  final AuthService _authService;
  final MobileApiService _mobileApiService;
  final nameController = TextEditingController();
  final currentPasswordController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmDeleteController = TextEditingController();

  bool _loadingProfile = false;
  bool _savingName = false;
  bool _savingPassword = false;
  bool _updatingAvatar = false;
  bool _pickingAvatar = false;
  bool _deletingAccount = false;
  String? _error;
  String? _success;

  UserModel? get user => _authService.currentUser;
  bool get isLoadingProfile => _loadingProfile;
  bool get isSavingName => _savingName;
  bool get isSavingPassword => _savingPassword;
  bool get isUpdatingAvatar => _updatingAvatar;
  bool get isDeletingAccount => _deletingAccount;
  String? get errorMessage => _error;
  String? get successMessage => _success;

  Future<void> load() async {
    _loadingProfile = true;
    _error = null;
    notifyListeners();
    try {
      final me = await _mobileApiService.me();
      _authService.updateSession(user: me.user, subscription: me.subscription);
      nameController.text = me.user.fullName;
    } on ApiException catch (error) {
      _error = error.message;
    } finally {
      _loadingProfile = false;
      notifyListeners();
    }
  }

  Future<bool> saveName() async {
    final name = nameController.text.trim();
    if (name.isEmpty || name.length > 120) {
      _error = 'El nombre debe tener entre 1 y 120 caracteres.';
      notifyListeners();
      return false;
    }
    return _run(
      action: () => _authService.updateProfileName(name),
      success: 'Nombre actualizado.',
      setLoading: (value) => _savingName = value,
    );
  }

  Future<bool> savePassword() async {
    final next = newPasswordController.text;
    if (next.length < 8) {
      _error = 'La nueva contraseña debe tener al menos 8 caracteres.';
      notifyListeners();
      return false;
    }
    final current = user?.hasPassword == true
        ? currentPasswordController.text
        : null;
    final ok = await _run(
      action: () => _authService.changePassword(
        newPassword: next,
        currentPassword: current,
      ),
      success: 'Contraseña actualizada.',
      setLoading: (value) => _savingPassword = value,
    );
    if (ok) {
      currentPasswordController.clear();
      newPasswordController.clear();
    }
    return ok;
  }

  Future<bool> pickAndUploadAvatar() async {
    if (_pickingAvatar) return false;
    _pickingAvatar = true;
    try {
      final picker = ImagePicker();
      final shot = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 85,
      );
      if (shot == null) return false;
      final file = File(shot.path);
      final size = await file.length();
      if (size > 3 * 1024 * 1024) {
        _error = 'El avatar no puede superar 3 MB.';
        notifyListeners();
        return false;
      }
      return await _run(
        action: () => _authService.uploadAvatar(file),
        success: 'Avatar actualizado.',
        setLoading: (value) => _updatingAvatar = value,
      );
    } on PlatformException catch (e) {
      debugPrint('ProfileController: PlatformException ${e.code}: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('ProfileController: error picking avatar: $e');
      return false;
    } finally {
      _pickingAvatar = false;
    }
  }

  Future<bool> removeAvatar() {
    return _run(
      action: _authService.deleteAvatar,
      success: 'Avatar eliminado.',
      setLoading: (value) => _updatingAvatar = value,
    );
  }

  Future<bool> deleteAccount() async {
    final user = this.user;
    if (user == null) return false;
    try {
      _deletingAccount = true;
      _error = null;
      notifyListeners();
      if (user.hasPassword) {
        await _authService.deleteAccount(password: confirmDeleteController.text);
      } else {
        await _authService.deleteAccount(
          confirmEmail: confirmDeleteController.text.trim(),
        );
      }
      return true;
    } on ApiException catch (error) {
      _error = error.message;
      return false;
    } finally {
      _deletingAccount = false;
      notifyListeners();
    }
  }

  Future<bool> _run({
    required Future<void> Function() action,
    required String success,
    required void Function(bool value) setLoading,
  }) async {
    setLoading(true);
    _error = null;
    _success = null;
    notifyListeners();
    try {
      await action();
      _success = success;
      return true;
    } on ApiException catch (error) {
      _error = error.message;
      return false;
    } finally {
      setLoading(false);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmDeleteController.dispose();
    super.dispose();
  }
}
