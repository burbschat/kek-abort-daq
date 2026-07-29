import setupLibPaths # setup the runtime PYTHONPATH paths

import argparse
import pyrogue.pydm
from axi_soc_7000_core.hardware.red_pitaya_stemlab_125_14.gui.GuiTop import GuiTop


def main():

    # Set the argument parser
    parser = argparse.ArgumentParser()

    # Add arguments
    parser.add_argument(
        "--serverList",
        type     = str,
        required = False,
        default  = 'localhost:9099',
        help     = "ZeroMQ server's hostname or IP address:port",
    )

    # Get the arguments
    args = parser.parse_args()

    pyrogue.pydm.runPyDM(
        serverList=args.serverList,
        display_factory = lambda parent=None, args=[], macros=None: GuiTop(
            parent   = parent,
            args     = args + ['numAdcCh=2', 'numDacCh=0'],
            macros   = macros,
        ),
        sizeX    = 800,
        sizeY    = 800,
    )


if __name__ == "__main__":
    main()
