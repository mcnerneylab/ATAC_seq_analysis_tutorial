#!/bin/bash

#specify the input fastq files
fq_F=$1
fq_R=$2
run_macs2=$3
p_value=$4
project_dir=$5


#specify the location of reference genome fast file for bwa mem
GENOME_FASTA=/gpfs/data/mcnerney-lab/reference_genomes_CUX1_CASP_diff/FASTA_files/hg19/hg19_Ordered.fa

#specify the dir to the blasklist file
blacklist=/gpfs/data/mcnerney-lab/reference_genomes_CUX1_CASP_diff/blacklists/hg19-blacklist.v2.bed

#grab base name of the fastq files
base=`basename $fq_F .fastq.gz`
echo "Sample name is $base"


#specify the number of cores to use for various downstream analysis
cores=8


#create all the output directories
# The -p option means mkdir will create the whole dir if it does not exist and refrain from complaining if it does exist

mkdir -p $project_dir/output/bwa
mkdir -p $project_dir/output/bigwigs


# set up output filenames and locations

bwa_mem_out=$project_dir/output/bwa/${base}.sam

samtools_q30_in=$project_dir/output/bwa/${base}.sam
samtools_q30_out=$project_dir/output/bwa/${base}.q30.bam

samtools_sort_in=$project_dir/output/bwa/${base}.q30.bam
samtools_sort_out=$project_dir/output/bwa/${base}.q30.srt.bam

samtools_dedup_in=$project_dir/output/bwa/${base}.q30.srt.bam
samtools_dedup_out=$project_dir/output/bwa/${base}.q30.srt.dedup.bam

samtools_noMITO_in=$project_dir/output/bwa/${base}.q30.srt.dedup.bam
samtools_noMITO_out=$project_dir/output/bwa/${base}.q30.srt.dedup.noMITO.bam

bedtools_rm_blacklist_in=$project_dir/output/bwa/${base}.q30.srt.dedup.noMITO.bam
bedtools_rm_blacklist_out=$project_dir/output/bwa/${base}.q30.srt.dedup.noMITO.blkrm.bam

bam_to_bed_in=$project_dir/output/bwa/${base}.q30.srt.dedup.noMITO.blkrm.bam
bam_to_bed_out=$project_dir/output/bwa/${base}.q30.srt.dedup.noMITO.blkrm.bed

bamCoverage_in=$project_dir/output/bwa/${base}.q30.srt.dedup.noMITO.blkrm.bam
bamCoverage_out=$project_dir/output/bigwigs/${base}.q30.srt.dedup.noMITO.blkrm.bw

#run the jobs


#genome alignment
echo "Run bwa mem"

cd $project_dir/input

module load gcc/12.1.0
module load intel/2022.2
module load llvm/14.0.5
module load bwa/0.7.17


bwa mem -t $cores \
$GENOME_FASTA \
$fq_F \
$fq_R \
> $bwa_mem_out



#filter and clean bam files
echo "Run samtools filter"

module load gcc/12.1.0
module load intel/2022.2
module load llvm/14.0.5
module load samtools/1.17

#q30 filtering
samtools view -bSh -q 30 -o $samtools_q30_out $samtools_q30_in

#sort
samtools sort -o $samtools_sort_out $samtools_sort_in

#dedup
samtools rmdup $samtools_dedup_in $samtools_dedup_out

#remove mitochondrial reads
samtools view -h $samtools_noMITO_in | awk '{if($3 != "chrM" && $3 != "chrUn"){print $0}}' | samtools view -hb > $samtools_noMITO_out

#index and generate bai file
samtools index $samtools_noMITO_out

echo "run bedtools to remove blacklist regions from bam files"

module load gcc/12.1.0
module load intel/2022.2
module load llvm/14.0.5
module load bedtools/2.30.0

bedtools intersect -abam $bedtools_rm_blacklist_in -b $blacklist -v > $bedtools_rm_blacklist_out

#now let's convert the bam to bed file. This is because the ATAC-specific MACS2 configuration requires bed as input
echo "convert bam to bed file"
bedtools bamtobed -i $bam_to_bed_in > $bam_to_bed_out


#remove the intermediate index file
rm *.dedup.bam.bai

echo "index the final bam file"
samtools index $bedtools_rm_blacklist_out

#generate bigwig files
#you need deepTools for this, and deepTools could be called on as long as you loaded the correct python version, so you don't need to load deepTools separately.
echo "generating bigwig files"

module load gcc/12.1.0
module load intel/2022.2
module load llvm/14.0.5
module load bedtools/2.30.0
module load python/3.10.5

bamCoverage -b $bamCoverage_in -o $bamCoverage_out



#macs2 peak calling
#macs2 peak calling
if [[ $run_macs2=true ]]; then

    echo "Running macs2 analysis"

    # Check if p value is specified
    if [[ -z $p_value ]]; then
        echo "Error: p value must be specified with -macs2."
        exit 1
    fi
 
    mkdir -p $project_dir/output/macs2
    macs2_outdir=$project_dir/output/macs2

    module load gcc/12.1.0
    module load intel/2022.2
    module load llvm/14.0.5
    module load python/3.10.5

    macs2 callpeak -t $bam_to_bed_out \
                       -f BED \
                       -g hs \
                       -n $base \
                       --nomodel \
                       --shift -75 \
                       --extsize 150 \
                       --call-summits \
                       -p $p_value \
                       -B \
                       --outdir $macs2_outdir


else
    echo "Skipping the macs2 peak calling analysis. You can run it separately"
fi






