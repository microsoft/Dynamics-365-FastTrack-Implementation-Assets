
# Commerce clickstream ML prediction
Dataset download > [Ad impressions with clicks dataset](https://www.kaggle.com/c/avazu-ctr-prediction/data)

The use case here is of a Commerce company that has an ecommerce website as well as traditional retail stores. They want to analyse the online clickstream data to better understand their customers. We will use a sample clickstream dataset from the data science website Kaggle. We will start with the Ingest and Exploration of data. Next we create features and train and evaluate the ML model. We will join this data with Dynamics products table to try to analyse if products influence the ML model result. The goal of this workflow is to create a machine learning model that, given a new ad impression, predicts whether or not there will be a click. We will also do features exploration to see what features influence the prediction most. We have a big dataset so we will go with supervised learning which relies on historical data to build a model to predict the result of the next observation.

Clickstream data is data about how users interact with your ecommerce websites, what ads they click, what products they view, which pages they spend most time on. It is behavioural data that can give you insights into your products and customers so you can better market to your customer base.

There are two notebooks, one for Synapse and one for Databricks. Its the same code but slight differences in syntax. 
