var path = require('path');
var webpack = require(path.join(__dirname, "webpack-base.config"));

webpack.output["path"] =
    path.resolve(__dirname, '../../__www-dist-cabal/task-view');

webpack.devServer["contentBase"] =
    path.resolve(__dirname, "../../__www-dist-cabal/task-view");

module.exports = webpack;
