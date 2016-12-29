#!/usr/bin/env nextflow

/*
vim: syntax=groovy
-*- mode: groovy;-*-
 *
 * Copyright (c) 2013-2016, Centre for Genomic Regulation (CRG).
 * Copyright (c) 2013-2016, Paolo Di Tommaso and the respective authors.
 *
 *   This file is part of 'Nextflow'.
 *
 *   Nextflow is free software: you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, either version 3 of the License, or
 *   (at your option) any later version.
 *
 *   Nextflow is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU General Public License for more details.
 *
 *   You should have received a copy of the GNU General Public License
 *   along with Nextflow.  If not, see <http://www.gnu.org/licenses/>.
 */
 
/*
 * Defines the pipeline inputs parameters (giving a default value for each for them) 
 * Each of the following parameters can be specified as command line options
 */
params.query = "$baseDir/examples/data/sample.fa"
params.db = "$baseDir/examples2/blast-db/pdb/tiny"
params.out = "results.local.txt"
params.s3_bucket = "s3://${NXF_username}-irish-bucket"
params.chunkSize = 100 

/*
if (params.profile == "aws") {
    s3_db_path = params.s3_bucket + "/" + file(params.db).parent
    params.db = "${NXF_AWS_efs_mnt}/${params.db}"
    params.out = "${params.s3_bucket}/results.cloud.txt"
    error "no aws yet"
}
else if (params.profile == "standard") {
    s3_db_path = ''
}
else {
    error "Invalid params.profile ${params}"
}
*/

db_name = file(params.db).name
db_path = file(params.db).parent


/* 
 * Given the query parameter creates a channel emitting the query fasta file(s), 
 * the file is split in chunks containing as many sequences as defined by the parameter 'chunkSize'.
 * Finally assign the result channel to the variable 'fasta' 
 */
Channel
    .fromPath(params.query)
    .splitFasta(by: params.chunkSize)
    .set { fasta }

/*
process if_aws_download_database_from_s3_to_efs {
    when:
    params.profile == "aws"

    script:
    """
    #!/usr/bin/env bash
    
    if [ ! -s "${db_path}" ]; then
        echo "file does not exist ${db_path}" >out3.out
        aws s3 cp --recursive "${s3_db_path}" "${db_path}"
    else
        echo "file exists ${db_path}" >out3.out
    fi
    """    
}
*/


/* 
 * Executes a BLAST job for each chunk emitted by the 'fasta' channel 
 * and creates as output a channel named 'top_hits' emitting the resulting 
 * BLAST matches  
 */
process blast {
    input:
    file 'query.fa' from fasta
    file db_path

    output:
    file top_hits

    """
    blastp -db $db_path/$db_name -query query.fa -outfmt 6 > blast_result
    cat blast_result | head -n 10 | cut -f 2 > top_hits
    """
}


/* 
 * Each time a file emitted by the 'top_hits' channel an extract job is executed 
 * producing a file containing the matching sequences 
 */
process extract {
    input:
    file top_hits
    file db_path

    output:
    file sequences

    """
    blastdbcmd -db $db_path/$db_name -entry_batch top_hits | head -n 10 > sequences
    """
}

/* 
 * Collects all the sequences files into a single file 
 * and prints the resulting file content when complete 
 */ 
sequences
    .collectFile(name: params.out)
    .println { file -> "matching sequences (${params.out}):\n ${file.text}" }
