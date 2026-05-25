/// Lightweight script for validating daily refresh date logic.
///
/// Run manually with:
/// `dart test_daily_refresh.dart`
void main() {
  final today = DateTime(2026, 1, 10);
  final tomorrow = today.add(const Duration(days: 1));
  final todayDate = _formatDate(today);
  final tomorrowDate = _formatDate(tomorrow);

  assert(todayDate == '2026-01-10');
  assert(tomorrowDate == '2026-01-11');
  assert(todayDate != tomorrowDate);

  String? savedDate;
  assert(_shouldRefreshDaily(savedDate, todayDate));

  savedDate = _markAsRefreshed(todayDate);
  assert(!_shouldRefreshDaily(savedDate, todayDate));

  savedDate = null;
  assert(_shouldRefreshDaily(savedDate, tomorrowDate));

  final failedRefreshSavedDate = _markAsRefreshedOnlyAfterSuccess(
    previousSavedDate: savedDate,
    date: tomorrowDate,
    apiCallSucceeded: false,
  );
  assert(failedRefreshSavedDate == null);
  assert(_shouldRefreshDaily(failedRefreshSavedDate, tomorrowDate));

  final successfulRefreshSavedDate = _markAsRefreshedOnlyAfterSuccess(
    previousSavedDate: failedRefreshSavedDate,
    date: tomorrowDate,
    apiCallSucceeded: true,
  );
  assert(successfulRefreshSavedDate == tomorrowDate);
  assert(!_shouldRefreshDaily(successfulRefreshSavedDate, tomorrowDate));
}

String _formatDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

bool _shouldRefreshDaily(String? savedDate, String currentDate) {
  return savedDate == null || savedDate != currentDate;
}

String _markAsRefreshed(String date) => date;

String? _markAsRefreshedOnlyAfterSuccess({
  required String? previousSavedDate,
  required String date,
  required bool apiCallSucceeded,
}) {
  if (!apiCallSucceeded) return previousSavedDate;
  return _markAsRefreshed(date);
}
