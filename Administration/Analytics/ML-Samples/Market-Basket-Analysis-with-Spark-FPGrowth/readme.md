# Market Basket Analysis with Spark FPGrowth (Data mining)
#### Dataset download > 
* #### [Instacart](https://www.kaggle.com/c/instacart-market-basket-analysis)

#### Library used >
* #### [Spark FPGrowth](https://spark.apache.org/docs/latest/mllib-frequent-pattern-mining.html#fp-growth)

Mining frequent items, itemsets, subsequences, or other substructures is usually among the first steps to analyze a large-scale dataset, which has been an active research topic in data mining for years. We refer users to Wikipedia’s association rule learning for more information. spark.mllib provides a parallel implementation of FP-growth, a popular algorithm to mining frequent itemsets.

Market basket analysis may provide the retailer with information to understand the purchase behavior of a buyer. This information will enable the retailer to understand the buyer's needs and rewrite the store's layout accordingly, develop cross-promotional programs, or even capture new buyers (much like the cross-selling concept). An apocryphal early illustrative example for this was when one super market chain discovered in its analysis that male customers that bought diapers often bought beer as well, have put the diapers close to beer coolers, and their sales increased dramatically. Although this urban legend is only an example that professors use to illustrate the concept to students, the explanation of this imaginary phenomenon might be that fathers that are sent out to buy diapers often buy a beer as well, as a reward. This kind of analysis is supposedly an example of the use of data mining. A widely used example of cross selling on the web with market basket analysis is Amazon.com's use of "customers who bought book A also bought book B", e.g. "People who read History of Portugal were also interested in Naval History".

This is a series of two notebooks - first to prepare the data tables and second for Exploratory data analysis and ML. Notebooks are written in Azure Synapse using PySpark, Scala and SQL queries. With minor changes to magic commands, notebooks can be taken to Databricks too.

