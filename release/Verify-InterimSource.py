"""Verify the narrow production delta against the published Alpha.2 tag."""
import argparse, hashlib, json, subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--source-root',type=Path,default=Path(__file__).resolve().parents[1]);p.add_argument('--repo-root',type=Path);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
src=a.source_root.resolve();repo=(a.repo_root or src).resolve();git=['git','-c','safe.directory='+str(repo).replace('\\','/'),'-C',str(repo)]
base='v0.1.0-alpha.2';parent=subprocess.check_output(git+['rev-parse',base+'^{}'],text=True).strip()
assert parent=='11af11a6da7ef102e45d1e50f209ddf268a21d73'
paths=subprocess.check_output(git+['ls-tree','-r','--name-only',base,'SoMRandomizer','SoMRandomizer.sln','LICENSE'],text=True).splitlines()
allowed={'SoMRandomizer/SoMRandomizer.csproj','SoMRandomizer/config/settings/OpenWorldSettings.cs','SoMRandomizer/forms/MainForm.cs','SoMRandomizer/forms/MainForm_UiOptionsInitialization.cs','SoMRandomizer/processing/openworld/OpenWorldStartingLocation.cs','SoMRandomizer/processing/openworld/events/FlammieLogicIntroEvent.cs','SoMRandomizer/processing/openworld/events/OpenWorldSupportingMapChanges.cs','SoMRandomizer/processing/openworld/randomization/OpenWorldLocationPrizeMatcher.cs','SoMRandomizer/processing/openworld/randomization/OpenWorldSimulator.cs','SoMRandomizer/processing/common/TripleTonpoleBossArenaRedirect.cs','SoMRandomizer/processing/openworld/randomization/OpenWorldResultInjector.cs'}
changed=[]
for path in paths:
 old=subprocess.check_output(git+['show',base+':'+path]);now=(src/path).read_bytes()
 if old.replace(b'\r\n',b'\n')!=now.replace(b'\r\n',b'\n'):changed.append(path)
assert set(changed)==allowed,changed
assert len(paths)==490
assert not list(src.glob('SoMRandomizer/**/*WeaponPower*'))
for name in ['AcceptedNativeDoomArena','NativeSlimeArenaRendering','AcceptedWallVisuals']:
 assert not (src/'SoMRandomizer/processing/common'/(name+'.cs')).exists()
a.output.parent.mkdir(parents=True,exist_ok=True)
a.output.write_text(json.dumps(dict(Base=parent,ProductionFiles=len(paths),Changed=changed,OtherProductionFilesUnchanged=True,ExperimentalClassesExcluded=True),indent=2))
print('PASS: exactly eleven reviewed production files differ; other published sources/resources and boss selection are unchanged.')
