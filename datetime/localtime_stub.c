#include <moonbit.h>
#include <stdint.h>
#include <string.h>
#include <time.h>

#ifdef _WIN32
static int dateutil_localtime_tm(int64_t t, struct tm *out) {
  __time64_t tt = (__time64_t)t;
  return _localtime64_s(out, &tt) == 0;
}
static long dateutil_gmtoff(int64_t t, struct tm *lt) {
  /* Interpret the local civil fields as if they were UTC: the difference
     to the real instant is the offset (no DST adjustment involved). */
  struct tm copy = *lt;
  __time64_t as_utc = _mkgmtime64(&copy);
  if (as_utc == -1) return 0;
  return (long)((int64_t)as_utc - t);
}
static const char *dateutil_zone(struct tm *lt) {
  static char buf[64];
  size_t n = strftime(buf, sizeof buf, "%Z", lt);
  buf[n] = 0;
  return buf;
}
#else
static int dateutil_localtime_tm(int64_t t, struct tm *out) {
  time_t tt = (time_t)t;
  return localtime_r(&tt, out) != NULL;
}
static long dateutil_gmtoff(int64_t t, struct tm *lt) {
  (void)t;
  return (long)lt->tm_gmtoff;
}
static const char *dateutil_zone(struct tm *lt) {
  return lt->tm_zone ? lt->tm_zone : "";
}
#endif

MOONBIT_FFI_EXPORT int32_t dateutil_localtime(int64_t t, int32_t *out) {
  struct tm lt;
  if (!dateutil_localtime_tm(t, &lt)) return 0;
  out[0] = lt.tm_year + 1900;
  out[1] = lt.tm_mon + 1;
  out[2] = lt.tm_mday;
  out[3] = lt.tm_hour;
  out[4] = lt.tm_min;
  out[5] = lt.tm_sec;
  out[6] = lt.tm_isdst;
  out[7] = (int32_t)dateutil_gmtoff(t, &lt);
  return 1;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t dateutil_localtime_zone(int64_t t) {
  struct tm lt;
  const char *zone = "";
  if (dateutil_localtime_tm(t, &lt)) zone = dateutil_zone(&lt);
  int32_t len = (int32_t)strlen(zone);
  moonbit_bytes_t bytes = moonbit_make_bytes(len, 0);
  memcpy(bytes, zone, len);
  return bytes;
}

MOONBIT_FFI_EXPORT void dateutil_tzset(void) {
#ifdef _WIN32
  _tzset();
#else
  tzset();
#endif
}
