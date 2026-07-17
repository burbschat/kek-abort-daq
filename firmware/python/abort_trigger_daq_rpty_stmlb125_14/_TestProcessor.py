import pyrogue as pr
import rogue.interfaces.stream as ris
import numpy as np


class TestProcessor(pr.DataReceiver):
    # Init method must call the parent class init
    def __init__(self, *args, **kwargs):
        pr.Device.__init__(self, *args, **kwargs)
        ris.Slave.__init__(self)
        pr.DataReceiver.__init__(self, enableOnStart=True, hideData=True, *args, **kwargs)

        # Not saving config/state to YAML
        guiGroups = ["NoStream", "NoState", "NoConfig"]

        # Remove data variable from stream and server
        self.Data.addToGroup("NoServe")
        self.Data.addToGroup("NoStream")
        self.Data.addToGroup("NoStatus")

    # Method which is called when a frame is received
    def process(self, frame):
        with self.root.updateGroup():
            # Convert the frame data into a numpy 16-bit integer array
            dat = frame.getNumpy(0, frame.getPayload()).view(np.uint32)
            print(dat)
