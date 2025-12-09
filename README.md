# EagleImp-RAP

*EagleImp-RAP* is implemented as a DNAnexus applet to run the [EagleImp]{https://github.com/ikmb/eagleimp} software on the UK Biobank Research Access Platform (UKB-RAP) in order to enable haplotype phasing and genotype imputation with UK Biobank haplotype reference panels.

EagleImp-RAP was developed following the DNAnexus developer guidelines at https://documentation.dnanexus.com/developer/apps/intro-to-building-apps.

Using the *dx-app-wizard* from the *dxtools* package, we generated a standardized UKB-RAP applet structure containing the execution *bash* script, a *.json* configuration file and a template directory structure for required binaries and libraries. *EagleImp*, *htslib* and *bcftools* were compiled for the UKB-RAP target environment. We also added a pre-compiled version of Intel's *libtbb* (as required by *EagleImp*).

The execution script handles argument parsing, retrieval and indexing of input files, and downloading the selected UKB reference panel from a predefined location within UKB-RAP. After running *EagleImp* on the acquired virtual machine (VM), the script collects and returns all output files to the user’s project space.

Chromosome X input files require special handling, as male samples are haploid in nonPAR regions and diploid in PAR1/2. The applet therefore splits chromosome X into PAR1, nonPAR and PAR2 segments, processes each region using the appropriate reference panel, and merges the results into a unified output file.