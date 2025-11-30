#!/usr/bin/env python3

# /// script
# requires-python = ">=3.12"
# dependencies = ["icalendar", "pytz", "ics-query"]
# ///

import sys
import argparse
from icalendar import Calendar
from datetime import datetime, timedelta
import pytz

def verb_print(msg, verbose):
  if verbose:
    print(msg)

def main():
  parser = argparse.ArgumentParser()
  parser.add_argument('ics', nargs='+')
  parser.add_argument('--output', '-o', required=False)
  parser.add_argument('--conky', action='store_true')
  parser.add_argument('--verbose', '-v', action='store_true', default=False)
  args = parser.parse_args()

  events = {}
  colors = {}

  for cal_file in args.ics:
    verb_print(f"Processing {cal_file}", args.verbose)
    color = 'white'
    if ':' in cal_file:
      cal_file, color = cal_file.split(':')

    # Remove the extension and any path
    cal_name = cal_file.split('/')[-1].split('.')[0]
    try:
      cal = Calendar.from_ical(open(cal_file, 'rb').read())
    except ValueError:
      print(f"ERROR: Could not parse ics data of {cal_file}, skipping", file=sys.stderr)
      continue

    colors[cal_name] = color

    # EVENTS
    for event in cal.walk('vevent'):
      start_dt = event['dtstart'].dt
      end_dt = event['dtend'].dt
      # Extract the date, start and end times in local time
      # date: YYYYMMDD
      # start: HH:MM
      # end: HH:MM
      local_tz = pytz.timezone('America/New_York')

      # Handle both date and datetime objects
      if isinstance(start_dt, datetime):
          # Convert naive datetime to UTC if needed
          if start_dt.tzinfo is None:
              start_dt = pytz.UTC.localize(start_dt)
          start_dt = start_dt.astimezone(local_tz)
      else:  # date object
          # Convert date to datetime at midnight Local Time
          start_dt = datetime.combine(start_dt, datetime.min.time())
          start_dt = local_tz.localize(start_dt)

      if isinstance(end_dt, datetime):
          # Convert naive datetime to UTC if needed
          if end_dt.tzinfo is None:
              end_dt = pytz.UTC.localize(end_dt)
          end_dt = end_dt.astimezone(local_tz)
      else:  # date object
          # Convert date to datetime at midnight Local Time
          end_dt = datetime.combine(end_dt, datetime.min.time())
          end_dt = local_tz.localize(end_dt)
      date = start_dt.strftime('%Y%m%d')
      start = start_dt.strftime('%H:%M')
      end = end_dt.strftime('%H:%M')

      # Check if start date is before today
      if date < datetime.now().strftime('%Y%m%d'):
          continue

      # Calculate the number of days the event spans
      # We need to use the local dates for this
      start_date_local = start_dt.date()
      end_date_local = end_dt.date()
      
      # If end_dt is exactly midnight, it effectively ends on the previous day for display purposes
      # UNLESS it's the same as start time (zero duration)
      if end_dt.hour == 0 and end_dt.minute == 0 and end_dt > start_dt:
          end_date_local -= timedelta(days=1)

      delta_days = (end_date_local - start_date_local).days

      for i in range(delta_days + 1):
          current_day = start_date_local + timedelta(days=i)
          current_date_str = current_day.strftime('%Y%m%d')
          
          # Skip if this day is in the past
          if current_date_str < datetime.now().strftime('%Y%m%d'):
              continue

          day_start = '00:00'
          day_end = '24:00' # Or maybe just show start time if it's start day

          if i == 0: # First day
              day_start = start
              if delta_days == 0: # Single day event
                  day_end = end
              else:
                  day_end = '24:00'
          elif i == delta_days: # Last day
              day_start = '00:00'
              day_end = end
          else: # Middle days
              day_start = '00:00'
              day_end = '24:00'

          if day_start == day_end and day_start == '00:00':
               # This might happen if we adjusted end_date_local back but logic still hit here?
               # Or if it's a 0 duration event at midnight?
               pass
          
          if day_start == day_end: # all day event logic from before, or just same time
            if day_start == '00:00' and day_end == '00:00':
                 # It's an all day event usually represented as 00:00 to 00:00 next day
                 # But we adjusted end date, so for single day all-day event:
                 # start=00:00, end=00:00 (next day) -> delta=0.
                 # Wait, if start=00:00, end=00:00 next day. 
                 # start_date = D, end_date = D+1. 
                 # end_dt is midnight, so end_date_local becomes D.
                 # delta_days = 0.
                 # i=0. day_start='00:00'. day_end='00:00' (original end time was 00:00 next day, but here we want to show it as all day)
                 pass
            pass

          # Re-apply the all-day check for the specific day entry
          if day_start == day_end and day_start == '00:00':
              # This is likely an all-day event
              pass
          
          # If it's a multi-day event, we might want to indicate it in the time range
          # But the request is just to handle it properly.
          
          if current_date_str not in events:
            events[current_date_str] = []
          
          events[current_date_str].append({
              'summary': event['summary'],
              'cal_name': cal_name,
              'start': day_start,
              'end': day_end
          })

  # Write the events to the output file
  # sort them by start date
  # print: start, end, name, summary
  events = sorted(events.items(), key=lambda x: x[0])

  output_txt = ""
  for date, sub_events in events:
    if args.conky:
      output_txt += f"-- {date}\n"
    else:
      output_txt += f"# {date}\n"
    sorted_sub_events = sorted(sub_events, key=lambda x: x['start'])
    for event in sorted_sub_events:
      if event['start'] == event['end']:
        time_range = 'All Day'
      else:
        time_range = f"{event['start']} - {event['end']}"

      color = colors.get(event['cal_name'], 'white')
      if args.conky:
        summary = event['summary']
        # clean #${} from text
        summary = summary.replace('#', r'\#').replace('$', r'$$').replace('{', r'\{').replace('}', r'\}').replace('`', r'\`')
        summary_words = summary.split(' ')
        # sentence split after 30 characters, keep full words
        splitc=30
        summary = ''
        while len(summary_words) > 0:
          if splitc <= 0:
            summary += "\n     "
            splitc=30
          word = summary_words.pop(0)
          summary += word + ' '
          splitc -= len(word)
        output_txt += '${color ' + color + '}' + time_range + ':${color white} ' + summary + '\n'
      else:
        output_txt += f" - {time_range} ({event['cal_name']}): {event['summary']}\n"
    output_txt += "\n"

  if args.output:
    with open(args.output, 'w') as f:
      f.write(output_txt)
      verb_print(f"Events written to {args.output}", args.verbose)
  else:
    print(output_txt)

if __name__ == "__main__":
  main()