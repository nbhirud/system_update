conda deactivate; 
# TODO - replace ENVNAME
conda env remove --name ENVNAME; 

# conda clean --tarballs; # -t stands for tarballs
conda clean -t

#conda update -n base -c defaults conda # do if using conda and not mamba

conda install -n base conda-forge::mamba; 
# TODO - replace PROJECTPATH and yml file path which contains details of creating ENVNAME
mamba env create --file PROJECTPATH/conda-environment.py312.yml; 
conda activate ENVNAME 

# Useful when using spyder or vscode
conda install ipykernel

conda clean --tarballs;

#####################
