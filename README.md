# DailyReport

## Ready for Use


To Add source file 
````
HTTP POST http://localhost:2000/job
{
    "name": "employee_details",
    "source": "/Users/regupathyb/projects/elixir/daily_dumb/sources/100Records.csv",
    "mapping": []
}

````
To Initiate the work 

```
AppNodeManager.start_work("morining_report")
```
