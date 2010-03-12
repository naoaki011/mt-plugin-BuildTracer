# BuildTracer

## About

BuildTracer is Movable Type template visualizer. It helps with the writing,
performance tuning, and analysis of MT templates. BuildTracer logs the rebuild
sequence of each MT generated page, visualizes the block structure of MT tags,
and shows how long each tag takes to publish in an individual template.

 * Visualize the block structure of MT tags
 * Trace the result of `<mt:if>` evaluation
 * Display the current instance of an MT variable
 * Display the processing time of each sequence

## Versions

 * 0.5 works with MT 4.3.
 * 0.4 works with MT 4.2?
 * 0.3.1 works with MT 4.1.

## Installation

Two directories, "plugins" and "mt-static" are included in the plugin. Upload
plugins/BuildTracer and mt-static/plugins/BuildTracer to your Movable Type
installation directory.

## Usage

Once installed, a command "FileInfo" will appear in each blog's Manage menu.
Go to Manage -> File Info, and click on an index template to view the trace
result Time stamps are displayed next to each template block to indicate how
long they take to evaluate/publish, as well as an overall time for the entire
template.

This plugin works fine with Firefox 2 and above. It may work on Internet
Explorer 7, but does not work on Internet Explorer 6.

## Credit

Originally written by Akira Sawada.

Blog: <http://blog.aklaswad.com/>

Original plugin page: <http://mt.aklaswad.com/plugins/buildtracer.html>
