import os
import yaml

TARGET_DIR = "/home/sean/code/eseries/kubernetes/ozone/santricity"

# A basic parser isn't great because it removes comments, so let's just do it cleanly with sed/python line replacement where we replace emptyDir with nothing and we add a volumeClaimTemplate to the StatefulSet.
