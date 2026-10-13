# Coros reply fixtures

Real replies from the owner's Coros account, read on 2 Oct 2026 through the COROS MCP. Each file holds the reply text after decoding the JSON-encoded string, which is exactly what the parsers receive.

These contain the owner's health data and GPS start points. They stay on this laptop; don't publish them.

| File | Tool | Notes |
| --- | --- | --- |
| sleep_hrv_7d.txt | querySleepHrv, 7 days | **Trimmed:** the raw time series is cut to two points per night (the app never reads it). The assessment section is verbatim. Today (2 Oct) is missing from the assessment and marked "no official sleep HRV value" in the series. |
| sleep_hrv_1d_no_data.txt | querySleepHrv, 1 day | Verbatim. The "No data" form of a missing night. |
| resting_hr_30d.txt | queryRestingHeartRate, 30 days | Verbatim. Several "No data" days. |
| training_load_7d.txt | queryTrainingLoadAssessment, 7 days | Verbatim. Includes the 2.11 Excessive spike. |
| sleep_overview_7d.txt | querySleepOverview, 7 days | Verbatim. **The sleep source for the morning check.** 2 Oct has no Main Sleep (watch not worn overnight) and a nap 09:32 to 10:27. Note the two durations formats: `6h 53min` and `50min`. |
| daily_health_7d.txt | queryDailyHealthData, 7 days | Verbatim. 2 Oct's 55-minute "sleep" is a nap: the owner didn't wear the watch overnight. The header's resting HR and HRV baseline are not the values the app uses. |
| training_schedule_week.txt | queryTrainingSchedule, 28 Sep to 4 Oct | Verbatim. Coded workout names, no easy/hard type. |
| sport_records_18d.txt | querySportRecords, 15 Sep to 2 Oct | Verbatim. Strength and gym cardio records break a line mid-record. |
| user_info.txt | queryUserInfo | Verbatim, from the M0 inspect run. No timezone field. |
| sleep_hrv_low_rating.txt | querySleepHrv, 7 days to 16 Jul | Verbatim, from the phone's first 12-week import. Contains the "Low" rating. |
| sleep_overview_legacy.txt | querySleepOverview, July | Verbatim. Mixes the legacy `Main Sleep:` format with the current one; a night without Daily Sleep (26 Jul); a legacy nap note. |
| sleep_overview_not_available.txt | querySleepOverview, August to early September | Verbatim. "Sleep detail for this day is not available yet." on 29 to 31 Aug. |
| training_plan_details_4d.txt | queryTrainingPlanDetails, 1 to 4 Oct | Verbatim (decoded), 2 Oct 2026. The real names behind schedule codes S5715 to S5809 (L28); a strength day that MCP marks as degraded. |
| training_plan_details_4w.txt | queryTrainingPlanDetails, 5 Oct to 1 Nov | Verbatim (decoded), 5 Oct 2026. Rest days, two-course days (run + strength), the 15k to 23k long-run jump, a "7k Easy" set to 10 km, a threshold session and a marathon-pace run. |
| sleep_hrv_no_nights.txt | querySleepHrv, 1 day (4 Oct) | Verbatim. No night at all: the time series section is replaced by "No sleep HRV time series data found in the last 1 days." |
| training_schedule_none.txt | queryTrainingSchedule, 5 Oct (rest day) | Verbatim. The whole reply is "No training schedule found." with no header. |
| daily_health_3d.txt | queryDailyHealthData, days 3 (3 to 5 Oct) | Verbatim, fetched 5 Oct 2026 evening. "Calories" is active calories (540 kcal by evening on a 35-minute day), not total energy. Today is partial. |
| sport_records_none.txt | querySportRecords, 2010 to 2024 | Verbatim, 7 Oct 2026. The whole reply when a range has no activities; the owner's history starts in 2025. |
| run_2026-10-07.fit | GPS track of a 35-minute outdoor run, 7 Oct 2026 | Rebuilt from the real Coros FIT file as a minimal valid FIT (file_id plus 2,101 record messages with timestamp and position; 2,093 with a fix), every position moved +0.5 degrees in latitude and longitude so the route doesn't show where the owner lives. The decoder was checked against the original file point for point. |
| fit_url.txt | queryActivityFitFileDownloadUrls, labelId 480868826783711233 | 7 Oct 2026, with the Coros user ID in the path replaced by zeros: these links need no login, so the real ID plus an activity ID would let anyone download the run. |

**Privacy edits for the public repo (13 Oct 2026):** start coordinates in `sport_records_18d.txt` and the FIT track are moved +0.5 degrees in latitude and longitude; the birth date in `user_info.txt` is changed (age unchanged); the Coros user ID in `fit_url.txt` is zeroed. Everything else is verbatim.
