json.today_logs @today_logs, partial: "api/activity_logs/activity_log", as: :activity_log
json.week_logs @week_logs, partial: "api/activity_logs/activity_log", as: :activity_log
json.month_logs @month_logs, partial: "api/activity_logs/activity_log", as: :activity_log
json.old_logs @old_logs, partial: "api/activity_logs/activity_log", as: :activity_log
