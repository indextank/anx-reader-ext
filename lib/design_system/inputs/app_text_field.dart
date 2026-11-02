import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.label,
    this.hintText,
    this.helperText,
    this.errorText,
    this.controller,
    this.initialValue,
    this.style,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.keyboardType,
    this.textInputAction,
    this.focusNode,
    this.autovalidateMode = AutovalidateMode.onUserInteraction,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.prefixIcon,
    this.suffixIcon,
    this.border,
    this.contentPadding,
    this.isCollapsed,
    this.isDense,
    this.inputFormatters,
  });

  final String? label;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final TextEditingController? controller;
  final String? initialValue;
  final TextStyle? style;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final GestureTapCallback? onTap;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final AutovalidateMode autovalidateMode;
  final bool obscureText;
  final bool enabled;
  final bool readOnly;
  final bool autofocus;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final InputBorder? border;
  final EdgeInsetsGeometry? contentPadding;
  final bool? isCollapsed;
  final bool? isDense;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final helperStyle =
        (theme.textTheme.bodySmall ?? DefaultTextStyle.of(context).style)
            .copyWith(color: theme.colorScheme.onSurfaceVariant);
    return TextFormField(
      controller: controller,
      initialValue: initialValue,
      style: style,
      validator: validator,
      forceErrorText: errorText,
      errorBuilder: (context, error) => Text(
        error,
        overflow: TextOverflow.visible,
      ),
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      onTap: onTap,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      focusNode: focusNode,
      autovalidateMode: autovalidateMode,
      obscureText: obscureText,
      enabled: enabled,
      readOnly: readOnly,
      autofocus: autofocus,
      maxLines: maxLines,
      minLines: minLines,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        helper: helperText == null
            ? null
            : DefaultTextStyle(
                style: helperStyle,
                child: Text(
                  helperText!,
                  overflow: TextOverflow.visible,
                ),
              ),
        alignLabelWithHint: true,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        border: border,
        contentPadding: contentPadding,
        isCollapsed: isCollapsed ?? false,
        isDense: isDense,
      ),
    );
  }
}
