#!/bin/bash
#SBATCH -J PLUTO							# name of run
#SBATCH -p c79 						# partition name
#SBATCH --nodes=1             # number of nodes, set to SLURM_JOB_NUM_NODES
#SBATCH --ntasks=1            # number of total MPI processes, set to SLURM_NTASKS
#SBATCH -t 30-00:00:00				# calculation time
#SBATCH -o stdout
#SBATCH -e stderr




cd "$SLURM_SUBMIT_DIR"
TIME=`date`
echo "start: ${TIME}"
echo "run dir: ${SLURM_SUBMIT_DIR}"

make clean
make
./pluto


TIME=`date`
echo "finish: ${TIME}"






###########################################################
##SBATCH --ntasks-per-node=1
##SBATCH --nodelist=node06
##SBATCH --dependency=afterany:  #no needed
##SBATCH --ntasks-per-node=36

####SBATCH --nodelist=node03


#module load slurm/18.08.5-2 compiler/gcc-6.3.1 openmpi/4.0.0/gcc-6.3.1
#module load slurm/18.08.5-2 compiler/intel-19.0.2.187 openmpi/4.0.0/intel-19.0.2.187

###NCPU=1
###export OMP_NUM_THREADS=36
##export OMP_NUM_THREADS=1
###mpirun -np ${NCPU} ${PROG} >${LOG}
###srun -n ${NCPU} --mpi=pmi2 ${PROG} > ${LOG}
##
##${PROG} >${LOG}
