# DailyReport

## Ready for Use

Application created to run multiple instance in a single nodes.

> iex --sname node1 -S mix

> iex --sname node2 -S mix

> iex --sname node3 -S mix

All these nodes are automatically joined each other 

Post the job through Rest API 

To initiate the report gathering 

> AppNodeManager.start("test")

run the above command in any iex terminal




## To Add source file 
````
HTTP POST http://localhost:2000/job
{
    "name": "employee_details_medium",
    "source": "/Users/regupathyb/projects/elixir/daily_dumb/sources/1000Records.csv",
    "mapping": [
        {"column": "Half of Joining",
         "to" :"h_join",
         "type" : "string"}
    ]
}

````
database column mapping automatically happen when your not specified in the mapping sections

for example a column name is "Date of Join" then it convert into dabase column as 'date_of_join'


## To Initiate the work 

```
AppNodeManager.start_work("morining_report")
```

## System Design Diagram 
![system design](priv/Daily%20Report%20-%20Daily%20Report%20Design%20diagram.jpg)
