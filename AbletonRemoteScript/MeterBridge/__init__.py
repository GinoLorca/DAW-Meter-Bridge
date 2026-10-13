"""MeterBridge: Ableton Live MIDI Remote Script for DAW Meter Bridge.

Live imports this package and calls create_instance() when the script is chosen
in a Control Surface slot (Input and Output: None). The script streams track state
and meters to the macOS app over UDP on 127.0.0.1 and applies the app's commands.
See docs/PROTOCOL.md in the repository.

Runs on Live 11 (Python 3.7) and Live 12 (Python 3.11): Python 3.7 syntax and
stdlib only. Nothing here imports Live at module level, so the pure modules can be
tested outside Live.
"""


def create_instance(c_instance):
    """Entry point Live calls to create the control surface."""
    from .live_surface import MeterBridgeSurface

    return MeterBridgeSurface(c_instance)
