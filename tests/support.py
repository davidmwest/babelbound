"""Repository paths for synthetic, offline Python tests."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "hammerspoon"
sys.path.insert(0, str(SOURCE))
