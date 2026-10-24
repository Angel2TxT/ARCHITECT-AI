import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:movil_architect/core/theme/app_colors.dart';
import 'package:movil_architect/views/legal/legal_views.dart';

class LoginAppMark extends StatelessWidget {
  const LoginAppMark({super.key});

  static const _logoSize = 120.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Image.asset(
          'assets/icons/logo.png',
          width: _logoSize,
          height: _logoSize,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
        const SizedBox(height: 16),
        Text(
          'ARCHITECT',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 4,
          ),
        ),
      ],
    );
  }
}

class LoginPillField extends StatelessWidget {
  const LoginPillField({
    super.key,
    required this.controller,
    required this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.autocorrect = true,
    this.onSubmitted,
    this.onChanged,
    this.suffix,
  });

  final TextEditingController controller;
  final String hint;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool autocorrect;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: isDark ? colorScheme.surfaceContainerHighest : AppColors.loginFieldFill,
        borderRadius: BorderRadius.circular(999),
        border: isDark ? Border.all(color: colorScheme.outlineVariant) : null,
      ),
      alignment: Alignment.center,
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        autocorrect: autocorrect,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        style: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: isDark
                ? colorScheme.onSurface.withValues(alpha: 0.45)
                : AppColors.iosHint,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          suffixIcon: suffix == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: suffix,
                ),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 32,
            minHeight: 32,
          ),
        ),
      ),
    );
  }
}

class LoginPrimaryButton extends StatelessWidget {
  const LoginPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = isDark ? Colors.white : Colors.black;
    final fgColor = isDark ? Colors.black : Colors.white;
    final disabledBg = isDark ? Colors.white38 : Colors.black54;

    return SizedBox(
      height: 56,
      width: double.infinity,
      child: FilledButton(
        onPressed: isLoading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: fgColor,
          disabledBackgroundColor: disabledBg,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        child: isLoading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: fgColor,
                ),
              )
            : Text(label),
      ),
    );
  }
}

class LoginSocialDivider extends StatelessWidget {
  const LoginSocialDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark ? const Color(0xFF3A3A3E) : AppColors.iosDivider;

    return Row(
      children: [
        Expanded(child: Divider(color: dividerColor, height: 1)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'O CONTINÚA CON',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
            ),
          ),
        ),
        Expanded(child: Divider(color: dividerColor, height: 1)),
      ],
    );
  }
}

class LoginGoogleButton extends StatelessWidget {
  const LoginGoogleButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 52,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
          backgroundColor: isDark
              ? colorScheme.surfaceContainerHighest
              : AppColors.loginFieldFill,
          elevation: 0,
          side: isDark
              ? BorderSide(color: colorScheme.outlineVariant)
              : BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              'assets/icons/google_logo.svg',
              width: 22,
              height: 22,
            ),
            const SizedBox(width: 12),
            const Text(
              'Google',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LoginLegalFooter extends StatelessWidget {
  const LoginLegalFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final linkColor = isDark ? Colors.white : AppColors.ink;

    return Text.rich(
      TextSpan(
        style: const TextStyle(
          color: AppColors.muted,
          fontSize: 12,
          height: 1.45,
          fontWeight: FontWeight.w400,
        ),
        children: [
          const TextSpan(text: 'Al continuar, aceptas nuestros '),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TermsOfServiceView(),
                  ),
                );
              },
              child: Text(
                'Términos de Servicio',
                style: TextStyle(
                  color: linkColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
          const TextSpan(text: ' y '),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const PrivacyPolicyView(),
                  ),
                );
              },
              child: Text(
                'Política de Privacidad',
                style: TextStyle(
                  color: linkColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
