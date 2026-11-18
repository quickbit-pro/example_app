/// Format in one pass so braces in customer-provided values stay literal.
String formatAppMessage(String template,
        [Map<String, Object?> values = const {}]) =>
    template.replaceAllMapped(RegExp(r'\{(p\d+)\}'), (match) {
      final name = match.group(1)!;
      return values.containsKey(name) ? '${values[name]}' : match.group(0)!;
    });
