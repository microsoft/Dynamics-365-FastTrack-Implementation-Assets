# Product recommendation with Google Tensorflow

#### Dataset download > 
* #### [Instacart](https://www.kaggle.com/c/instacart-market-basket-analysis)

#### Concepts, tools, libraries used >
* #### [Wide & Deep](https://ai.googleblog.com/2016/06/wide-deep-learning-better-together-with.html)
* #### [Tensorflow](https://www.tensorflow.org/)
* #### [Petastorm](https://github.com/uber/petastorm)
* #### [Hyperopt](https://github.com/hyperopt/hyperopt)
* #### [MLFlow](https://mlflow.org/)

This is a series of three notebooks. The purpose of these notebooks is to prepare the datasets, engineer the features and train, evaluate & deploy a "Wide & Deep" collaborative filter recommender using Tensorflow DNNLinearCombinedClassifier estimator API.
This API combines a linear classifier with a DNN (deep neural network). The linear classifier is "wide", and deals well with having lots of features, whilst the NN (Neural network) is "deep", and deals with complex relationships within particularly important features. By combining the two models and averaging their outputs, in some way, we may arrive at a more accurate overall prediction. 

These notebooks were run on Azure Synapse CPU based pool. One step in notebook#3 for hyperparameter search, takes few hours, you may get faster results with GPU based pools. Before you run notebook#3 on Synapse, you need to define the packages needed (Tensorflow, Petastorm etc) in a separate file and load them.

