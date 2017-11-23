
rule vardict:
    input:
        bam="star/final/{sample}.bam",
        bai="star/final/{sample}.bam.bai",
        reference=config["vardict"]["reference"],
        regions=config["vardict"]["regions"]
    output:
        temp("vardict/per_sample/{sample}.vcf")
    params:
        options=config["vardict"]["extra"],
        options_vcf=config["vardict"]["extra_vcf"],
        sample="{sample}"
    conda:
        path.join(workflow.basedir, "envs/vardict.yaml")
    shell:
        "vardict -G {input.reference} -b {input.bam} -N {params.sample}"
        " {params.options} {input.regions}"
        " | teststrandbias.R"
        " | var2vcf_valid.pl -N {params.sample} {params.options_vcf}"
        " > {output}"


rule compress_sample_vcf:
    input:
        "vardict/per_sample/{sample}.vcf"
    output:
        "vardict/per_sample/{sample}.vcf.gz"
    conda:
        path.join(workflow.basedir, "envs/bcftools.yaml")
    shell:
        "bcftools view --output-file {output[0]} --output-type z {input[0]} && "
        "bcftools index --tbi {output[0]}"


rule vardict_merge:
    input:
        expand("vardict/per_sample/{sample}.vcf.gz", sample=get_samples())
    output:
        temp("vardict/merged/calls.vcf")
    params:
        options=config["vardict_merge"]["extra"]
    conda:
        path.join(workflow.basedir, "envs/bcftools.yaml")
    shell:
        "bcftools merge {params.options} {input} > {output[0]}"


if config["options"]["vardict_annotate"] == "snpeff":

    rule vardict_snpeff:
        input:
            temp("vardict/merged/calls.vcf")
        output:
            vcf=temp("vardict/merged/calls.snpeff.vcf"),
            stats="vardict/merged/calls.snpeff_summary.html"
        params:
            database=config["vardict_snpeff"]["database"],
            extra=config["vardict_snpeff"]["extra"] + ' -noStats'
        log:
            "logs/snpeff.log"
        conda:
            path.join(workflow.basedir, "envs/snpeff.yaml")
        shell:
            "snpEff"
            " -v {params.extra}"
            " -stats {output.stats}"
            " {params.database} {input[0]}"
            " > {output.vcf} 2> {log}"

    prev_vcf = "vardict/merged/calls.snpeff.vcf"

elif config["options"]["vardict_annotate"] == "vep":

    rule vardict_vep:
        input:
            "vardict/merged/calls.vcf"
        output:
            vcf=temp("vardict/merged/calls.vep.vcf"),
            summary="vardict/merged/calls.vep.vcf_summary.html"
        params:
            species=config["vardict_vep"]["species"],
            extra=config["vardict_vep"]["extra"]
        log:
            "logs/ensembl-vep.log"
        conda:
            path.join(workflow.basedir, "envs/ensembl-vep.yaml")
        shell:
            "vep --offline --vcf --force_overwrite"
            " --input_file {input[0]}"
            " --output_file {output.vcf}"
            " --species {params.species}"
            " {params.extra} 2> {log}"


    rule vardict_vep_table:
        input:
            "vardict/merged/calls.vcf"
        output:
            vcf="vardict/merged/calls.vep_table.txt",
            summary="vardict/merged/calls.vep_table.txt_summary.html"
        params:
            species=config["vardict_vep"]["species"],
            extra=config["vardict_vep"]["extra"]
        log:
            "logs/ensembl-vep.log"
        conda:
            path.join(workflow.basedir, "envs/ensembl-vep.yaml")
        shell:
            "vep --offline --force_overwrite"
            " --input_file {input[0]}"
            " --output_file {output.vcf}"
            " --species {params.species}"
            " {params.extra} 2> {log}"

    prev_vcf = "vardict/merged/calls.vep.vcf"
else:
    prev_vcf = "vardict/merged/calls.vcf"


rule compress_vcf:
    input:
        prev_vcf
    output:
        "vardict/final/calls.vcf.gz"
    conda:
        path.join(workflow.basedir, "envs/bcftools.yaml")
    shell:
        "bcftools view --output-file {output[0]} --output-type z {input[0]} && "
        "bcftools index --tbi {output[0]}"


rule snpsift_extract_fields:
    input:
        "vardict/final/calls.vcf.gz"
    output:
        "vardict/final/calls.txt"
    conda:
        path.join(workflow.basedir, "envs/snpsift.yaml")
    params:
        fields=config["snpsift_extract_fields"]["fields"],
        sample_fields=config["snpsift_extract_fields"]["sample_fields"],
        extra=config["snpsift_extract_fields"]["extra"],
        samples=get_samples()
    script:
        path.join(workflow.basedir, "scripts/snpsift_extract_fields.py")
