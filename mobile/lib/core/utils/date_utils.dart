import 'package:intl/intl.dart';

String formatRelativeTime(DateTime? date) {
  if (date == null) return 'Sin fecha';
  final local = date.toLocal();
  final now = DateTime.now();
  final diff = now.difference(local);

  if (diff.inMinutes < 60 && now.day == local.day) {
    if (diff.inMinutes < 1) return 'Ahora';
    return 'Hace ${diff.inMinutes} min';
  }
  if (diff.inHours < 24 && now.day == local.day) {
    return 'Hace ${diff.inHours} horas';
  }
  if (now.difference(local).inDays == 1) return 'Ayer';
  return DateFormat('d MMM').format(local);
}

String formatChatDateTime(DateTime? date) {
  if (date == null) return '';
  return DateFormat('dd MMM yyyy, HH:mm').format(date.toLocal());
}
