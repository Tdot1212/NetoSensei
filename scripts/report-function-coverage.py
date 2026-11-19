#!/usr/bin/env python3
"""Export all compiler-instrumented functions without equating execution with accuracy."""
import argparse
import json
from pathlib import Path
from datetime import datetime
from zoneinfo import ZoneInfo

parser = argparse.ArgumentParser()
parser.add_argument('coverage_json', type=Path)
parser.add_argument('output_dir', type=Path)
args = parser.parse_args()
data = json.loads(args.coverage_json.read_text())
app = next(target for target in data['targets'] if target['name'] == 'NetoSensei.app')
functions = []
files = []
for file in app['files']:
    path = file['path']
    relative = path.split('/NetoSensei/', 1)[-1]
    entries = file.get('functions', [])
    files.append({'file': relative, 'lineCoverage': file['lineCoverage'], 'coveredLines': file['coveredLines'],
                  'executableLines': file['executableLines'], 'instrumentedFunctions': len(entries),
                  'functionsEntered': sum(item['executionCount'] > 0 for item in entries)})
    for item in entries:
        functions.append({'file': relative, 'line': item['lineNumber'], 'name': item['name'],
                          'executionCount': item['executionCount'], 'lineCoverage': item['lineCoverage'],
                          'evidence': 'entered by this test run' if item['executionCount'] else 'not entered by this test run',
                          'accuracyCertification': False})
summary = {'generatedAt': datetime.now(ZoneInfo('Asia/Shanghai')).isoformat(),
           'meaning': 'Compiler functions include closures, property accessors and synthesized Codable functions. Execution/line coverage is not branch coverage or physical accuracy validation.',
           'coveredLines': app['coveredLines'], 'executableLines': app['executableLines'],
           'lineCoverage': app['lineCoverage'], 'instrumentedFunctions': len(functions),
           'functionsEntered': sum(item['executionCount'] > 0 for item in functions),
           'files': files, 'functions': functions}
args.output_dir.mkdir(parents=True, exist_ok=True)
(args.output_dir / 'NetoSensei Function Coverage.json').write_text(json.dumps(summary, indent=2))
lines = ['NetoSensei function coverage — execution evidence, not accuracy certification', '',
         f"Application line coverage: {app['lineCoverage']:.2%}",
         f"Instrumented functions entered: {summary['functionsEntered']} / {len(functions)}", '',
         'All compiler-instrumented functions are listed in NetoSensei Function Coverage.json.',
         'An unexecuted function remains a test gap. A function entered once is not necessarily fully tested.', '',
         'Coverage by source file (includes compiler-generated functions and closures):']
for file in sorted(files, key=lambda item: (item['lineCoverage'], item['file'])):
    lines.append(f"{file['lineCoverage']:7.2%}  {file['functionsEntered']:4}/{file['instrumentedFunctions']:<4}  {file['file']}")
(args.output_dir / 'NetoSensei Coverage Gaps.txt').write_text('\n'.join(lines) + '\n')
print(json.dumps({key: summary[key] for key in ['lineCoverage','instrumentedFunctions','functionsEntered']}))
