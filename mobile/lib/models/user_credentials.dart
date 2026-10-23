class UserCredentials {
  const UserCredentials({
    required this.email,
    required this.password,
  });

  final String email;
  final String password;

  bool get isValid => email.trim().isNotEmpty && password.isNotEmpty;
}
