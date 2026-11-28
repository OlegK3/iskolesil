import 'dart:math';

import '../domain/models.dart';

const _months = [
  'янв.', 'февр.', 'марта', 'апр.', 'мая', 'июня',
  'июля', 'авг.', 'сент.', 'окт.', 'нояб.', 'дек.'
];
const _monthsFull = [
  'январь', 'февраль', 'март', 'апрель', 'май', 'июнь',
  'июль', 'август', 'сентябрь', 'октябрь', 'ноябрь', 'декабрь'
];
const _weekdaysShort = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];

String _two(int v) => v.toString().padLeft(2, '0');

String fmtDate(DateTime d) {
  final l = d.toLocal();
  return '${l.day} ${_months[l.month - 1]} ${l.year}';
}

String fmtTime(DateTime d) {
  final l = d.toLocal();
  return '${_two(l.hour)}:${_two(l.minute)}';
}

String fmtDateTime(DateTime d) => '${fmtDate(d)}, ${fmtTime(d)}';
String monthName(int month) => _monthsFull[month - 1];
String weekdayShort(DateTime d) => _weekdaysShort[d.weekday - 1];

String _num(double v, int digits) =>
    v.toStringAsFixed(digits).replaceAll('.', ',');

/// Расстояние: значение и единица раздельно, для крупных цифр.
(String, String) distanceParts(double meters, MeasurementUnits u) {
  if (u == MeasurementUnits.imperial) {
    return (_num(meters / 1609.344, 2), 'ми');
  }
  if (meters < 1000) return (meters.round().toString(), 'м');
  return (_num(meters / 1000, meters < 100000 ? 2 : 1), 'км');
}

String fmtDistance(double meters, MeasurementUnits u) {
  final (v, unit) = distanceParts(meters, u);
  return '$v $unit';
}

(String, String) speedParts(double metersPerSecond, MeasurementUnits u) {
  if (u == MeasurementUnits.imperial) {
    return (_num(metersPerSecond * 2.236936, 1), 'ми/ч');
  }
  return (_num(metersPerSecond * 3.6, 1), 'км/ч');
}

String fmtSpeed(double mps, MeasurementUnits u) {
  final (v, unit) = speedParts(mps, u);
  return '$v $unit';
}

String fmtDuration(int seconds) {
  final s = max(0, seconds);
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  if (h > 0) return '$h:${_two(m)}:${_two(sec)}';
  return '${_two(m)}:${_two(sec)}';
}

/// Короткая длительность для статистики: «2 ч 05 мин».
String fmtDurationLong(int seconds) {
  final s = max(0, seconds);
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  if (h > 0) return '$h ч ${_two(m)} мин';
  return '$m мин';
}

String fmtElevation(double? meters, MeasurementUnits u) {
  if (meters == null) return '—';
  if (u == MeasurementUnits.imperial) return '${(meters * 3.28084).round()} фт';
  return '${meters.round()} м';
}

String fmtBytes(int bytes) {
  if (bytes < 1024) return '$bytes Б';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} КБ';
  if (bytes < 1024 * 1024 * 1024) {
    return '${_num(bytes / (1024 * 1024), 1)} МБ';
  }
  return '${_num(bytes / (1024 * 1024 * 1024), 2)} ГБ';
}

String pluralRides(int n) {
  final n10 = n % 10, n100 = n % 100;
  if (n10 == 1 && n100 != 11) return '$n поездка';
  if (n10 >= 2 && n10 <= 4 && (n100 < 12 || n100 > 14)) return '$n поездки';
  return '$n поездок';
}

/// Название по умолчанию: «Вечерняя поездка — Барнаул».
String defaultRideTitle(DateTime startedAt, [String city = '']) {
  final h = startedAt.toLocal().hour;
  final part = h >= 5 && h < 12
      ? 'Утренняя'
      : h >= 12 && h < 18
          ? 'Дневная'
          : h >= 18 && h < 23
              ? 'Вечерняя'
              : 'Ночная';
  return city.isEmpty ? '$part поездка' : '$part поездка — $city';
}
