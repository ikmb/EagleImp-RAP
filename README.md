# EagleImp-RAP

*EagleImp-RAP* is implemented as a DNAnexus applet to run the [EagleImp]{https://github.com/ikmb/eagleimp} software on the UK Biobank Research Access Platform (UKB-RAP) in order to enable haplotype phasing and genotype imputation with UK Biobank haplotype reference panels.

EagleImp-RAP was developed following the DNAnexus developer guidelines at https://documentation.dnanexus.com/developer/apps/intro-to-building-apps.

Using the *dx-app-wizard* from the *dxtools* package, we generated a standardized UKB-RAP applet structure containing the execution *bash* script, a *.json* configuration file and a template directory structure for required binaries and libraries. *EagleImp*, *htslib* and *bcftools* were compiled for the UKB-RAP target environment. We also added a pre-compiled version of Intel's *libtbb* (as required by *EagleImp*).

The execution script handles argument parsing, retrieval and indexing of input files, and downloading the selected UKB reference panel from a predefined location within UKB-RAP. After running *EagleImp* on the acquired virtual machine (VM), the script collects and returns all output files to the user’s project space.

Chromosome X input files require special handling, as male samples are haploid in nonPAR regions and diploid in PAR1/2. The applet therefore splits chromosome X into PAR1, nonPAR and PAR2 segments, processes each region using the appropriate reference panel, and merges the results into a unified output file.


## Requirements and installation instructions

At the current stage *EagleImp-RAP* is not yet available as ready-to-use DNAnexus platform app. Thus, you need to use the command line interface of the DNAnexus and build your local *EagleImp-RAP* applet.

#### Requirements:

- **dxtools**: See [Command Line Quickstart]{https://documentation.dnanexus.com/getting-started/cli-quickstart} from the DNAnexus documentation how to set up the command line interface for the UKB-RAP on your system.

- **UKB reference files**: For now, the reference panel files in *.qref* format must be installed in a local DNAnexus project under `your_project:/qrefs/UKB/`.

#### Installation:

1. Navigate to the repository folder on your local machine:
```
cd  <path_to_repo>
```

2. Navigate to the root folder (or an alternative folder) in the DNAnexus where you want to install the applet.
```
dx cd /
```

3. Call `dx build` to build the applet in your project. (`-f` is only required if you want to overwrite an existing installation of *EagleImp-RAP*, e.g. for an update).
```
dx build -f ikmb-eagleimp
```

Now, the applet is ready to use on the DNAnexus.


## User options

*EagleIMP-RAP* provides the following user options. The first three are mandatory:

- `target`: The target file to be phased/imputed. Can be either in `.bcf` or `.vcf.gz` format. The same input file conventions as for [EagleImp]{https://github.com/ikmb/eagleimp} apply, i.e. the file must not contain data for more than one chromosome and the file name must start with the chromosome number, followed by a dot. A preceding 'chr' is allowed.
- `build`: The genome build of your input file. Either `hg19` or `hg38`.
- `reference`: One of the supported reference panels: `UKBcomplete`, `UKBmaf` or `1000G`.

The following options are optional and are exactly as in [EagleImp]{https://github.com/ikmb/eagleimp}:

- `skipPhasing`: Skip phasing step (input is already phased). default = `false`
- `skipImputation`: Skip imputation step (do phasing only). default = `false`
- `imputeInfo`: Choose which probability information should accompany the hard called genotypes in the output: `a`: allele dosages, `g`: genotype dosages, `p`: genotype probabilities. Can be arbitrarily combined. default = `a`
- `imputeR2filter`: Output contains only variants with an estimated R2 greater or equal to this filter value. default = `0`
- `imputeMAFfilter`: Output contains only variants with a minor allele frequency greater or equal to this filter value. default = `0`
- `outputPhasedFile`: Generates an additional output file that contains only the phased input. default = `false`
- `outputUnphased`: Sites excluded from phasing are included in the phased output (if enabled). default = `false`
- `allowRefAltSwap`: Allow target and reference variants to match if their reference and alternative alleles are swapped. default = `true`
- `allowStrandFlip`: Allow target and reference variants to match if their reference and alternative alleles are strand flipped. default = `false`
- `K`: K-best reference haplotypes are chosen for the phasing step prior to imputation. Either `10000` or `32768`. default = `10000`
- `maxChunkMemory`: Max memory (in GiB) used for chunks. `0` = auto (85% of free RAM), any other value overrides the automatic setting. Be careful, the VM may crash if the setting is too high. default = `0`

The output files are:

- A file containing the imputation output (not if `skipImputation` was set).
- A file containing only the output of the phasing step (only if `outputPhasedFile` was set).
- A file containing the (sample-wise) phasing confidences (not if `skipPhasing` was set).
- A file containg additional information for each variant.
- The log file.

**Note**: The output genotype files are in the same format as the target input, i.e. either `.bcf` or `.vcf.gz`.


## Usage examples

**Note**: The following examples expect the applet to be installed in the root directory of your active project. If not, please use the correct path to your applet when calling `dx run`.

**Note**: The same input file conventions as for [EagleImp]{https://github.com/ikmb/eagleimp} apply, i.e. the file must not contain data for more than one chromosome and the file name must start with the chromosome number, followed by a dot. A preceding 'chr' is allowed.

#### Single file:

To start phasing/imputation on a single file, simply copy that file to your project and run the applet with this file as input using `dx run`.
The example uses a folder `output` as output directory relative to the location of the target file.
The output is downloaded afterwards using `dx download`.

```
dx cd <some_path_in_your_project>
dx upload <target.vcf.gz>
dx run /ikmb-eagleimp -itarget=<target.vcf.gz> -ibuild=hg38 -ireference=UKBcomplete --folder=output --instance-type=mem3_ssd1_v2_x16 --priority=high
dx download -r output
```

You can adjust the options to your need or add additional options such as `-iallowStrandFlip=true` to your needs. You can also choose a different VM instance type, if you like.

**IMPORTANT**: Please note, that the minimum VM size for UKB imputation is 120 GB of RAM and 200 GB of hard disk space. We also recommend to always set the `--priority=high` option as UKB imputation takes time and thus, it is very likely that the job gets interrupted when started with lower priorities.

#### Batch processing:

In order to process a batch of files using a VM instance for each file, you can generate a batch file for your inputs and execute it.

The following command generates a batch file called `batch_example.0000.tsv`.
Inputs are expected to be in the current local folder and match with `chr<number>.*.vcf.gz`.

```
dx generate_batch_inputs -i target='(chr.*).*.vcf.gz' -o batch_example
```

Upload your input files to the DNAnexus and run the batch file:

```
dx cd <some_path_in_your_project>
dx upload chr*.vcf.gz
dx run /ikmb-eagleimp --batch-tsv=batch_example.0000.tsv -ibuild=hg38 -ireference=UKBcomplete --folder=output --instance-type=mem3_ssd1_v2_x16 --brief --yes --priority=high
dx download -r output
```

**Note**: The options `--brief` and `--yes` reduce the output of the run command and disable asking for confirmation.
