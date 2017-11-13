#!/usr/bin/en python3
# ---------------------------------------------------------------
# Title: Sampleclas.py - Create list with count of sample types based on filename
#
# Author: Rob Hamerling, Copyright (c) 2012..2017, all rights reserved.
#
# Adapted-by: Rob Hamerling 2017: converted to Python3
#
# Revision: $Revision$
#
# Compiler: N/A
#
# This file is part of jallib  http://jallib.googlecode.com
# Released under the BSD license
#              http://www.opensource.org/licenses/bsd-license.php
#
# Description:
#   Create a list with a count of sample types based on the filename.
#   It is assumed that the filename starts with PIC type, followed
#   by the name of the library for which the sample is a showcase.
#
# Sources:
#
# Notes:
#
# --------------------------------------------------------------

import os, sys

base       = os.path.join("/", "media", "nas", "jallib")    # local copy of Jallib base
smpdir     = os.path.join(base, "sample")                   # samples subdirectory
report     = "sampleclass.lst"                              # list in curent working directory

# --------------------------------------------------------------
# mainline
# --------------------------------------------------------------
def main():
   print("Collecting primary library usage")
   libcount = {}
   files = os.listdir(smpdir)                            # whole sample directory)
   files.sort()
   for file in files:
      fn = os.path.splitext(file)[0]                           # remove extension
      words = fn.split("_", 1)
      libname = words[1]                                 # 2nd part of filename
      libcount[libname] = libcount.get(libname, 0) + 1   # update/init counter
   try:
      with open(report, "w") as fr:
         keylist = sorted(libcount.keys())
         for lib in keylist:
            fr.write("%4d  %s\n" % (libcount[lib], lib))
   except:
      print("Feil to write output:", report)

   print("See", report, "for results.")


#  === E N T R Y   P O I N T ===

if (__name__ == "__main__"):

   main()


