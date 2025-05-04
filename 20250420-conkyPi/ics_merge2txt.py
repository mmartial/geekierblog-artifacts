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
      # Handle both date and datetime objects
      if isinstance(start_dt, datetime):
          # Convert naive datetime to UTC if needed
          if start_dt.tzinfo is None:
              start_dt = pytz.UTC.localize(start_dt)
      else:  # date object
          # Convert date to datetime at midnight UTC
          start_dt = datetime.combine(start_dt, datetime.min.time(), tzinfo=pytz.UTC)

      if isinstance(end_dt, datetime):
          # Convert naive datetime to UTC if needed
          if end_dt.tzinfo is None:
              end_dt = pytz.UTC.localize(end_dt)
      else:  # date object
          # Convert date to datetime at midnight UTC
          end_dt = datetime.combine(end_dt, datetime.min.time(), tzinfo=pytz.UTC)

      # Extract the date, start and end times in local time
      # date: YYYYMMDD
      # start: HH:MM
      # end: HH:MM
      local_tz = pytz.timezone('America/New_York')
      start_dt = start_dt.astimezone(local_tz)
      end_dt = end_dt.astimezone(local_tz)
      date = start_dt.strftime('%Y%m%d')
      start = start_dt.strftime('%H:%M')
      end = end_dt.strftime('%H:%M')

      # Check if start date is before today
      if date < datetime.now().strftime('%Y%m%d'):
          continue

      if start == end: # all day event
        start = '00:00'
        end = start

      # If the event date is mot in the dictionary, add it
      if date not in events:
        events[date] = []
      events[date].append({
          'summary': event['summary'],
          'cal_name': cal_name,
          'start': start,
          'end': end
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
        range = 'All Day'
      else:
        range = f"{event['start']} - {event['end']}"

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
        output_txt += '${color ' + color + '}' + range + ':${color white} ' + summary + '\n'
      else:
        output_txt += f" - {range} ({event['cal_name']}): {event['summary']}\n"
    output_txt += "\n"

  if args.output:
    with open(args.output, 'w') as f:
      f.write(output_txt)
      verb_print(f"Events written to {args.output}", args.verbose)
  else:
    print(output_txt)

if __name__ == "__main__":
  main()