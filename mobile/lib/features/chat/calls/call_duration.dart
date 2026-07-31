/// Call duration rendering.
///
/// One place decides how an elapsed call reads, so the call screen, the call
/// pill and the inbox preview can never drift apart. Render the result with the
/// tabular count style (`context.kt.count`) — the digits must not change width
/// as the timer ticks.
library;

/// Formats [value] as `m:ss` below one hour and `h:mm:ss` at or above one hour.
///
/// Sub-second precision is truncated, never rounded, so a formatted timer never
/// reads ahead of the elapsed time. Minutes and seconds below an hour are
/// written as `m:ss` — minutes unpadded, seconds always two digits. From one
/// hour onward both minutes and seconds pad to two digits and hours are
/// unpadded, so durations past 24 hours keep counting rather than wrapping.
/// Negative durations clamp to zero.
String formatCallDuration(Duration value) {
  final total = value.isNegative ? 0 : value.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  final paddedSeconds = seconds.toString().padLeft(2, '0');

  if (hours == 0) return '$minutes:$paddedSeconds';
  return '$hours:${minutes.toString().padLeft(2, '0')}:$paddedSeconds';
}

/// Parses a duration string produced by [formatCallDuration].
///
/// Accepts `m:ss` and `h:mm:ss`, with or without padding on the leading field.
/// Returns null for anything else — empty text, a missing or extra field, a
/// non-numeric field, or a minutes or seconds field outside 0–59 — so a
/// malformed stored string surfaces as an absent duration instead of a wrong
/// one. Parsing the output of [formatCallDuration] always yields the original
/// duration truncated to whole seconds.
Duration? parseCallDuration(String value) {
  final text = value.trim();

  final minuteForm = _minuteForm.firstMatch(text);
  if (minuteForm != null) {
    return Duration(
      minutes: int.parse(minuteForm.group(1)!),
      seconds: int.parse(minuteForm.group(2)!),
    );
  }

  final hourForm = _hourForm.firstMatch(text);
  if (hourForm != null) {
    return Duration(
      hours: int.parse(hourForm.group(1)!),
      minutes: int.parse(hourForm.group(2)!),
      seconds: int.parse(hourForm.group(3)!),
    );
  }

  return null;
}

/// `m:ss` — minutes 0–59, seconds as a two-digit 0–59 pair.
final RegExp _minuteForm = RegExp(r'^([0-5]?\d):([0-5]\d)$');

/// `h:mm:ss` — unbounded hours, then two two-digit 0–59 pairs.
final RegExp _hourForm = RegExp(r'^(\d+):([0-5]\d):([0-5]\d)$');
