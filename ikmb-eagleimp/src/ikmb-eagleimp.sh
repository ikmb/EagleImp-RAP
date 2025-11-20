#!/bin/bash
#
#    Copyright (C) 2025 by Lars Wienbrandt,
#    Institute of Clinical Molecular Biology, Kiel University
#
#    This file is part of ikmb-eagleimp.
#
#    ikmb-eagleimp is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    ikmb-eagleimp is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with ikmb-eagleimp. If not, see <https://www.gnu.org/licenses/>.
#

main() {

  # Prefix for references and genetic maps:
  # Now pointing to a local resource of the parent project.
  # Probably using a public project resource in the future?
  refproject="$DX_PROJECT_CONTEXT_ID:/refs"

  # available references
  refbase_1kg_hg19="/qrefs/1000G/hg19/##.genotypes.qref"
  refbase_1kg_hg38lift="/qrefs/1000G/hg38.lifted/chr##.20130502.genotypes.hg38lifted.qref"
  refbase_ukb_hg19="/qrefs/UKB/hg19.w20250818/##.ukb23374_v1_cfilter_restored_mac4.phased.w139525_20250818.hg19lifted.qref"
  refbase_ukb_hg38="/qrefs/UKB/hg38.w20250818/chr##.ukb23374_v1_cfilter_restored_mac4.phased.w139525_20250818.qref"
  refbase_ukb_maf_hg19="/qrefs/UKB/hg19.maf0.0001.w20250818/##.ukb23374_v1_cfilter_restored_mac4.phased.maf0.0001.w139525_20250818.hg19lifted.qref"
  refbase_ukb_maf_hg38="/qrefs/UKB/hg38.maf0.0001.w20250818/chr##.ukb23374_v1_cfilter_restored_mac4.phased.maf0.0001.w139525_20250818.qref"

  # genetic maps
  gmbase_hg19="/1000G/genetic_maps/hg19/genetic_map_hg19_chr##.txt"
  gmbase_hg38="/1000G/genetic_maps/hg38/genetic_map_hg38_chr##.txt"

  echo "target: '$target'"
  echo "reference: '$reference'"
  echo "build: '$build'"
  echo "allowRefAltSwap: '$allowRefAltSwap'"
  echo "allowStrandFlip: '$allowStrandFlip'"
  echo "imputeR2filter: '$imputeR2filter'"
  echo "imputeMAFfilter: '$imputeMAFfilter'"
  echo "imputeInfo: '$imputeInfo'"
  echo "K: '$K'"

  # Download target file into VM.
  # To recover the original filename, the output of "dx describe
  # "$target" --name" is used.

  dx download "$target"
  tgt=$(dx describe "$target" --name)

  # To report any recognized errors in the correct format in
  # $HOME/job_error.json the dx-jobutil-report-error utility
  # is used as follows:
  #
  #   dx-jobutil-report-error "My error message"
  #
  # However, this entire bash script is executed with -e
  # when running in the cloud, so any line which returns a nonzero
  # exit code will prematurely exit the script; if no error was
  # reported in the job_error.json file, then the failure reason
  # will be AppInternalError with a generic error message.

  # get chromosome number from input file name (it's a relative file name without path already)
  chrprefixed=${tgt%%.*} # strip all from the first dot
  chr=${chrprefixed/chr/} # remove "chr" -> now, only the number should be left

  # determine input format -> will also be the output format
  if [[ $tgt == *.bcf ]]; then
    fmt=b
    ext=".bcf"
  else # we only have these two options
    fmt=z
    ext=".vcf.gz"
  fi

  # parse imputation options
  unset allrefalt
  if [[ $allowRefAltSwap == true ]]; then
    allrefalt="--allowRefAltSwap"
  fi

  unset allstrandflip
  if [[ $allowStrandFlip == true ]]; then
    allstrandflip="--allowStrandFlip"
  fi

  unset r2filter
  if (( $(echo "$imputeR2filter > 0" | bc -l) )); then
    r2filter="--imputeR2filter $imputeR2filter"
  fi

  unset maffilter
  if (( $(echo "$imputeMAFfilter > 0" | bc -l) )); then
    maffilter="--imputeMAFfilter $imputeMAFfilter"
  fi

  impinfo="--imputeInfo $imputeInfo"
  k="--K $K"

  # names of final result files
  resultadd=."$reference"
  if [[ -n "$r2filter" ]]; then
    resultadd="$resultadd"."${imputeR2filter}r2"
  fi
  if [[ -n "$maffilter" ]]; then
    resultadd="$resultadd"."${imputeMAFfilter}maf"
  fi
  tgtbase="${tgt%$ext}"
  imputed="$tgtbase$resultadd".imputed$ext
  confidences="$tgtbase$resultadd".phased.confidences
  varinfo="$tgtbase$resultadd".varinfo
  logfile="$tgtbase$resultadd".log

  # Everything from here will be logged in a separate log file that
  # will be made available as another result file.

  {
    echo
    echo "Starting EagleImp imputation app:"
    echo
    echo -n "Check if input filename complies with the specification... "

    # check if the file is named correctly
    check=0
    if [[ $chr =~ ^[0-9]+$ ]]; then
      if (( $chr > 23 )); then
        check=1
      fi
    elif [[ $chr != "X" && $chr != "X_PAR1" && $chr != "X_nonPAR" && $chr != "X_PAR2" && $chr != "23_PAR1" && $chr != "23_nonPAR" && $chr != "23_PAR2" ]]; then
      check=1
    fi

    if [[ $check != 0 ]]; then
      echo "no"
      dx-jobutil-report-error "ERROR: Ensure that your target file is named in compliance with the specification, i.e. the chromosome number (1-23) at the beginning separated with a '.'-character. A preceding 'chr' is allowed as well as 'X' instead of the number. 'X' or '23' may also be suffixed with '_PAR1', '_nonPAR' or '_PAR2'."
      exit 1
    else
      echo "yes"
    fi

    # VM specifications
    mem="$(grep MemFree /proc/meminfo | awk '{print $2}')"
    disk="$(df -P . | tail -1 | awk '{print $4}')"

    echo
    echo "VM specifications:"
    echo "  Available RAM: $mem kiB == $( bc <<< 'scale=3; '$mem' / 1024 / 1024' ) GiB"
    echo "  Available disk space: $disk kiB == $( bc <<< 'scale=3; '$disk' / 1024 / 1024' ) GiB"
    echo -n "Check if the VM is capable to handle the imputation... "
    if [[ "$reference" != "1000G" ]] && (( $mem < 120000000 || $disk < 200000000 )); then
      echo "no"
      dx-jobutil-report-error "ERROR: Ensure that the VM has at least 120 GB of RAM and 200 GB of disk space for UKB imputation."
      exit 1
    fi
    echo "yes"

    # check if filter values are valid
    echo
    echo -n "Check if filter values are valid... "
    if (( $(echo "$imputeR2filter < 0" | bc -l) || $(echo "$imputeR2filter > 1" | bc -l) || $(echo "$imputeMAFfilter < 0" | bc -l) || $(echo "$imputeMAFfilter > 0.5" | bc -l) )); then
      echo "no"
      dx-jobutil-report-error "ERROR: Invalid filters. Ensure 0 <= R2 <= 1 and 0 <= MAF <= 0.5."
      exit 1
    else
      echo "yes"
    fi

    # check, if this is chromosome X (without explicit PAR region declaration)
    # -> splitting required
    splitx=0
    if [[ $chr == 23 || $chr == X ]]; then
      splitx=1
    fi

    # choose reference and genetic map according to user selection
    if [[ "$build" == "hg19" ]]; then
      gmbase="$gmbase_hg19"
      if [[ "$reference" == "UKBcomplete" ]]; then
        refbase="$refbase_ukb_hg19"
      elif [[ "$reference" == "UKBmaf" ]]; then
        refbase="$refbase_ukb_maf_hg19"
      else
        refbase="$refbase_1kg_hg19"
      fi
    else # hg38
      gmbase="$gmbase_hg38"
      if [[ "$reference" == "UKBcomplete" ]]; then
        refbase="$refbase_ukb_hg38"
      elif [[ "$reference" == "UKBmaf" ]]; then
        refbase="$refbase_ukb_maf_hg38"
      else
        refbase="$refbase_1kg_hg38lift"
      fi
    fi

    # choose genetic map file
    # special treatment for chrX as we don't seperate the PAR regions for the genetic map
    if [[ $splitx == 0 && ( $chr == X* || $chr == 23* ) ]]; then
      # a PAR/nonPAR region is directly addressed
      if [[ $chr == X* ]]; then
        genmap="$refproject${gmbase/\#\#/X}"
      else
        genmap="$refproject${gmbase/\#\#/23}"
      fi
    else
      genmap="$refproject${gmbase/\#\#/$chr}"
    fi

    echo
    echo -n "Check if genetic map $genmap is available... "
    if ! {
      dx describe "$genmap" >/dev/null 2>&1
    }; then
      echo "no"
      dx-jobutil-report-error "ERROR: Ensure that the genetic map file is available at the correct location in your project: $genmap"
      exit 1
    else
      echo "yes"
    fi

    echo -n "Downloading genetic map... "
    if ! {
      dx download --no-progress $genmap
    }; then
      dx-jobutil-report-error "ERROR: Failed to download genetic map $genmap"
      exit 1
    fi
    echo "done"

    # strip file path from downloaded file as it is located directly in the home folder now
    genmap="${genmap##*/}"

    # take 85% of the available RAM for imputation chunks (and convert to GiB)
    mem="$(( $mem * 85 / 100 / 1024 / 1024 ))"

    # start timestamp for file processing
    procstart=$(date +%s)

    # split X, if required
    if [[ $splitx == 0 ]]; then
      # usual processing of a single file

      # reference file (replaces ## by the chromosome number)
      ref="$refproject${refbase/\#\#/$chr}"
      # process file
      process_file "$tgt" "$ref"

      # rename output files
      mv "${tgt%$ext}".imputed$ext "$imputed"
      mv "${tgt%$ext}".phased.confidences "$confidences"
      mv "${tgt%$ext}".varinfo "$varinfo"

    else
      # split X chromosome in PAR/nonPAR regions and process parts separately with final merging

      echo -n "Chromosome X requires splitting in PAR/nonPAR regions. Splitting... "

      if [[ "$build" == "hg19" ]]; then
        regpar1="1-2699520"
        regnonpar="2699521-154931043"
        regpar2="154931044-"
      else
        regpar1="1-2781479"
        regnonpar="2781480-155701382"
        regpar2="155701383-"
      fi

      if [[ $fmt == b ]]; then
        tgt_par1="${chrprefixed}_PAR1.bcf"
        tgt_nonpar="${chrprefixed}_nonPAR.bcf"
        tgt_par2="${chrprefixed}_PAR2.bcf"
      else
        tgt_par1="${chrprefixed}_PAR1.vcf.gz"
        tgt_nonpar="${chrprefixed}_nonPAR.vcf.gz"
        tgt_par2="${chrprefixed}_PAR2.vcf.gz"
      fi

      if ! {
        bcftools index $tgt
        bcftools view $tgt -r "23:$regpar1,chr23:$regpar1,X:$regpar1,chrX:$regpar1" -O$fmt -o "$tgt_par1"
        bcftools view $tgt -r "23:$regnonpar,chr23:$regnonpar,X:$regnonpar,chrX:$regnonpar" -O$fmt -o "$tgt_nonpar"
        bcftools view $tgt -r "23:$regpar2,chr23:$regpar2,X:$regpar2,chrX:$regpar2" -O$fmt -o "$tgt_par2"
      }; then
        dx-jobutil-report-error "ERROR: Splitting in PAR/nonPAR regions failed."
        exit 1
      fi

      echo "done"

      # Processing PAR/nonPAR regions
      echo
      echo "Processing PAR1..."

      ref_par1="$refproject${refbase/\#\#/${chr}_PAR1}"
      process_file "$tgt_par1" "$ref_par1"

      echo
      echo "Processing nonPAR..."

      ref_nonpar="$refproject${refbase/\#\#/${chr}_nonPAR}"
      process_file "$tgt_nonpar" "$ref_nonpar"

      echo
      echo "Processing PAR2..."

      ref_par2="$refproject${refbase/\#\#/${chr}_PAR2}"
      process_file "$tgt_par2" "$ref_par2"

      # merging result files
      echo
      echo "Merging/concatenating result files..."

      # imputed
      imp_par1="${tgt_par1/PAR1/PAR1.imputed}"
      imp_nonpar="${tgt_nonpar/nonPAR/nonPAR.imputed}"
      imp_par2="${tgt_par2/PAR2/PAR2.imputed}"
      files=""
      if [[ -f $imp_par1 ]]; then
        files="$files $imp_par1"
      fi
      if [[ -f $imp_nonpar ]]; then
        files="$files $imp_nonpar"
      fi
      if [[ -f $imp_par2 ]]; then
        files="$files $imp_par2"
      fi
      # assuming at least one file, otherwise there would have been an error beforehand
      if ! {
        bcftools concat $files -n -o "$imputed"
      }; then
        dx-jobutil-report-error "ERROR: Concatenating PAR/nonPAR regions failed."
        exit 1
      fi

      # confidences
      for conf in *PAR1.phased.confidences *nonPAR.phased.confidences *PAR2.phased.confidences; do
        echo "$conf:" >> "$confidences"
        cat "$conf" >> "$confidences"
        echo >> "$confidences"
      done

      # varinfo
      header=0
      for vinfo in *PAR1.varinfo *nonPAR.varinfo *PAR2.varinfo; do
        if [[ header == 0 ]]; then
          cat "$vinfo" > "$varinfo"
          header=1
        else
          tail -n +2 "$vinfo" >> "$varinfo"
        fi
      done
    fi

    # end timestamp for file processing
    procend=$(date +%s)
    proctime=$(( procend - procstart ))

    # start timestamp for upload
    uplstart=$procend

    echo
    echo -n "Uploading result files..."

    # upload result files from the VM to the parent project
    imputed_file=$(dx upload "$imputed" --brief)
    phasing_confidences=$(dx upload "$confidences" --brief)
    varinfo=$(dx upload "$varinfo" --brief)

    # The utility dx-jobutil-add-output is used to format and
    # add output variables to the job's output as appropriate for the output
    # class.
    dx-jobutil-add-output imputed_file "$imputed_file" --class=file
    dx-jobutil-add-output phasing_confidences "$phasing_confidences" --class=file
    dx-jobutil-add-output varinfo "$varinfo" --class=file

    # end timestamp for upload
    uplend=$(date +%s)
    upltime=$(( uplend - uplstart ))

    echo "done"
    echo "Upload time: $upltime seconds"
    echo
    echo "Total time: $(( proctime + upltime )) seconds"

    # log ends here
  } 2>&1 | tee -a log

  # Whenever an error was thrown, the process will have exited with an error code.
  # Unfortunately, the return value here belongs to "tee", but we can access PIPESTATUS.
  ret=${PIPESTATUS[0]}
  if [[ $ret != 0 ]]; then
    # simply exit as the error reason was already set
    exit $ret
  fi

  # This is to make the logfile name conform to the other output files.
  mv log "$logfile"
  # upload log
  log=$(dx upload "$logfile" --brief)
  dx-jobutil-add-output log "$log" --class=file

  exit 0
}

# Function that processes a single target file with EagleImp.
# Parameters are
# $1: target file (local)
# $2: reference file (global -> will be downloaded)
# NOTE: all variables we use here have a global context, so this function is NOT thread-safe!
process_file() {

  # We got tgt and ref as parameters, so I make them local here to shadow the global context.
  local tgt="$1"
  local ref="$2"

  echo
  echo -n "Check if reference file $ref is available... "
  if ! {
    dx describe "$ref" >/dev/null 2>&1
  }; then
    echo "no"
    dx-jobutil-report-error "ERROR: Ensure that the reference file is available at the correct location in your project: $ref"
    exit 1
  else
    echo "yes"
  fi

  # start timestamp for reference download
  dwnlstart=$(date +%s)

  echo -n "Downloading reference... "
  if ! {
    dx download --no-progress $ref
  }; then
    dx-jobutil-report-error "ERROR: Failed to download reference $ref"
    exit 1
  fi
  echo "done"

  # end timestamp
  dwnlend=$(date +%s)
  downloadtime=$(( dwnlend - dwnlstart ))

  echo "Download time: $downloadtime seconds"

  # strip file path from just downloaded file as it is located directly in the home folder now
  ref="${ref##*/}"

  # start timestamp for index
  idxstart=$(date +%s)

  echo
  echo -n "Run bcftools index $tgt... "
  if ! {
    bcftools index $tgt
  }; then
    echo "Index failed."
    dx-jobutil-report-error "ERROR: bcftools index $tgt failed."
    exit 1
  fi
  echo "done"

  # end timestamp for index
  idxend=$(date +%s)
  idxtime=$(( idxend - idxstart ))

  echo "Indexing time: $idxtime seconds"

  # EagleImp command
  cmd="eagleimp --target $tgt --ref $ref --geneticMap $genmap -O$fmt --maxChunkMemory $mem $allrefalt $allstrandflip $r2filter $maffilter $impinfo $k"

  # start timestamp for eagleimp
  eagleimpstart=$(date +%s)

  echo
  echo "Run EagleImp..."
  echo "$cmd"
  if ! {
    $cmd 2>&1
  }; then
    dx-jobutil-report-error "ERROR: Eagleimp failed. Command: $cmd"
    exit 1
  fi

  # end timestamp for eagleimp
  eagleimpend=$(date +%s)
  eagleimptime=$(( eagleimpend - eagleimpstart ))

  echo
  echo "EagleImp time: $eagleimptime seconds"
  echo "Total processing time for file $tgt: $(( downloadtime + idxtime + eagleimptime )) seconds"

}
