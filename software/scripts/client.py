import pyrogue as pr

import setupLibPaths
import abort_trigger_daq_rpty_stmlb125_14 as target

import argparse


def main():
    # Set the argument parser
    parser = argparse.ArgumentParser()

    # Add arguments
    parser.add_argument(
        "--ip",
        type=str,
        required=True,
        help="ETH Host Name (or IP address)",
    )

    # Get the arguments
    args = parser.parse_args()

    with target.Root(
        ip=args.ip,
        # pollEn      = args.pollEn,
        # initRead    = args.initRead,
        # defaultFile = args.defaultFile,
        # zmqSrvPort  = args.zmqSrvPort,
    ) as root:

        ######################
        # Development PyDM GUI
        ######################
        # if (args.guiType == 'PyDM'):
        #     axi_soc_ultra_plus_core.rfsoc_utility.pydm.runPyDM(
        #         serverList = root.zmqServer.address,
        #         ui       = f'{os.path.dirname(axi_soc_ultra_plus_core.rfsoc_utility.__file__)}/gui/GuiTop.py',
        #         sizeX    = 800,
        #         sizeY    = 800,
        #         numAdcCh = 4,
        #         numDacCh = 2,
        #     )

        #################
        # No GUI
        #################
        # elif (args.guiType == 'None'):
        print("Running without GUI...")
        pr.waitCntrlC()

        ####################
        # Undefined GUI type
        ####################
        # else:
        #     raise ValueError("Invalid GUI type (%s)" % (args.guiType) )


if __name__ == "__main__":
    main()
