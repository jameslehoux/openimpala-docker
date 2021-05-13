FROM centos:7
  
#    Container that contains all libraries needed to run OpenImpala
#      * Singularity integration with and use of MPI
#      * the steps necessary to enable MPI messaging over IB
#      * Build of AMReX libraries
#      * Build of Hypre solver
#      * HDF5 1.12.0
#      * HDF5 C++ API
#      * CMake
      
#    Note: the original recipe for enabling MPI messaging over IB is
#      * https://community.mellanox.com/docs/DOC-2431
#      * This recipe is adapted from M. Dutas hpc-mpi-benchmarks.sif

#    Usage: functions are installed as Singularity apps.  A few useful commands
#      * singularity apps container.simg
#      * singularity help --app diffusion container.simg
#      * singularity run --app diffusion container.simg



#    maintainer James Le Houx
#    version 1.5

  #
  # --- install compilers
RUN  yum install -y centos-release-scl-rh
RUN  yum install -y devtoolset-9

RUN  /bin/bash -c "source /opt/rh/devtoolset-9/enable"

  #
  # --- install verbs
RUN  yum groupinstall -y "Infiniband"
RUN  yum install	   -y libibverbs-devel
  
RUN  yum install -y gcc-c++ gcc-gfortran wget git rh-python36 hostname
RUN  yum --enablerepo=extras install -y epel-release
RUN  scl enable rh-python36 bash
RUN  yum install -y libtiff libtiff-devel python-pip boost169-devel.x86_64 
RUN  python -m pip --version
RUN  python -m pip install --upgrade pip

    #
    # --- install OpenMPI
ENV   OPENMPI_VERSION=3.1.4
RUN   wget https://download.open-mpi.org/release/open-mpi/v${OPENMPI_VERSION%??}/openmpi-${OPENMPI_VERSION}.tar.gz --no-check-certificate && \
      tar -xf openmpi-${OPENMPI_VERSION}.tar.gz
WORKDIR   openmpi-${OPENMPI_VERSION}/ 
RUN       ./configure \
          --prefix=/usr/local \
          --enable-orterun-prefix-by-default \
          --enable-mpirun-prefix-by-default  \
          --with-verbs 
RUN   make && \
      make install

WORKDIR /
    # Note: "--with-verbs" is not essential, as ibverbs support is picked up automatically
RUN  rm -fr openmpi-${OPENMPI_VERSION}*

    #
    # --- make OpenMPI libraries /usr/local/lib available
RUN    ldconfig
RUN    ldconfig /usr/local/lib
    
    #
    # --- install cmake
RUN    wget https://cmake.org/files/v3.12/cmake-3.12.3.tar.gz --no-check-certificate && \
       tar zxvf cmake-3.*
WORKDIR cmake-3.12.3
RUN     ./bootstrap --prefix=/usr/local && \
       make -j$(nproc) && \
       make install


WORKDIR /src

    #
    # --- install HDF5
ENV    HDF5_VERSION=1.12.0
RUN    wget https://support.hdfgroup.org/ftp/HDF5/releases/hdf5-1.12/hdf5-${HDF5_VERSION}/src/hdf5-${HDF5_VERSION}.tar.gz --no-check-certificate && \
       tar -xf hdf5-${HDF5_VERSION}.tar.gz 
WORKDIR hdf5-${HDF5_VERSION} 
RUN    CFLAGS="-O3 -mavx2" CXXFLAGS=${CFLAGS} FCFLAGS=${CFLAGS} && \
       CC=`type -p mpicc` FC=`type -p mpif90` && \
           ./configure  \
           --prefix=/opt/hdf5-parallel/${HDF5_VERSION}  \
           --enable-fortran  \
           --enable-fortran2003  \
           --enable-parallel  \
           --disable-tests  
RUN    make && \
       make install

WORKDIR /src
RUN    rm -fr hdf5-${HDF5_VERSION}/ hdf5-${HDF5_VERSION}.tar.gz

ENV    ROOT_HDF5=/opt/hdf5-parallel/1.12.0

    #
    # --- install HDF5 C++ api
ENV    CC=/opt/rh/devtoolset-9/root/usr/bin/gcc
ENV    CPP=/opt/rh/devtoolset-9/root/usr/bin/cpp
ENV    CXX=/opt/rh/devtoolset-9/root/usr/bin/c++
RUN    yum install -y python36-devel
RUN    yum install -y python36-setuptools
RUN    easy_install-3.6 pip && \
       python -m pip3 install conan 
RUN    conan config set general.revisions_enabled=True && \
       conan remote add ecdc https://artifactoryconan.esss.dk/artifactory/api/conan/ecdc && \
       conan remote add bincrafters https://bincrafters.jfrog.io/artifactory/api/conan/public-conan && \
       git clone -b v0.4.0 --single-branch https://github.com/ess-dmsc/h5cpp.git 
WORKDIR   h5cpp/build
RUN    cmake .. && \
       make && \  
       make install

WORKDIR /src
    #
    # --- install amrex
RUN    git clone -b 21.02 --single-branch https://github.com/AMReX-Codes/amrex.git
WORKDIR /src/amrex
RUN    ./configure --with-mpi yes --with-omp yes --enable-eb yes && \
       make && \
       make install
       
WORKDIR /src
    #
    # --- install hypre
RUN    git clone https://github.com/hypre-space/hypre.git
WORKDIR hypre/src 
RUN       ./configure && \
       make && \
       make install

WORKDIR /
COPY /src/amrex/tmp_install_dir/include /usr/include/amrex
COPY /src/amrex/tmp_install_dir/lib/* /usr/lib/
COPY /src/hypre/src/hypre/include /usr/include/hypre
COPY /src/hypre/src/hypre/lib/* /usr/lib
COPY /src/h5cpp/build/lib/* /usr/lib
COPY /src/hdf5-1.12.0/src/ /usr/include/hdf5
COPY /src/hdf5-1.12.0/hl/src/* /usr/include/hdf5

RUN    rm -rf /src
    
    #
    # --- install OpenImpala
RUN    git clone https://github.com/kramergroup/openImpala.git
WORKDIR openImpala 
RUN       make

#============================================================#
# environment: PATH, LD_LIBRARY_PATH, etc.
#============================================================#

ENV OPENMPI_VERSION=3.1.4
ENV OPENIMPALA_VERSION=1.0.0
ENV PATH=/opt/openmpi/${OPENMPI_VERSION}/bin:$PATH


ENV PATH=/opt/rh/devtoolset-9/root/usr/bin:${PATH}}
ENV LD_LIBRARY_PATH=/opt/rh/devtoolset-9/root/usr/lib64:/opt/rh/devtoolset-9/root/usr/lib:${LD_LIBRARY_PATH}
ENV LD_LIBRARY_PATH=/opt/rh/devtoolset-9/root/usr/lib64/dyninst:/opt/rh/devtoolset-9/root/usr/lib/dyninst:${LD_LIBRARY_PATH}
ENV LD_LIBRARY_PATH=/usr/local/lib64:/usr/lib:${LD_LIBRARY_PATH}
  
ENV LC_ALL=C


#============================================================#
# script to run with command "singularity run"
#============================================================#

