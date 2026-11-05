/*
DigiKala BI Analytics — 01_create_database.sql
Creates the DigikalaBI database and its two schemas.
SAFE: Creates missing objects only; does not delete existing objects or data.
Source: database/schema definitions from the supplied SSMS-generated script.sql.
*/
USE [master];
GO
IF DB_ID(N'DigikalaBI') IS NULL
BEGIN
    CREATE DATABASE [DigikalaBI];
END;
GO
USE [DigikalaBI];
GO
IF SCHEMA_ID(N'stg') IS NULL EXEC(N'CREATE SCHEMA [stg]');
IF SCHEMA_ID(N'dw')  IS NULL EXEC(N'CREATE SCHEMA [dw]');
GO
