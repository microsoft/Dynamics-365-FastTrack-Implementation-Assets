const path = require('path');
const TerserPlugin = require('terser-webpack-plugin');
module.exports = {
  mode: 'production',
  entry: {
    reactcomponents: './index.ts'
  },
  output: {
    path: path.resolve(__dirname, '../DistReact'),
    filename: '[name].js',
    library: '[name]',
    libraryTarget: 'umd',
    clean: true
  },
  resolve: {
    extensions: ['.ts', '.tsx', '.js']
  },
  module: {
    rules: [
      {
        test: /\.(ts|tsx)$/,
        exclude: [
          path.resolve(__dirname, 'node_modules') 
        ],
        use: 'babel-loader'
      },
      {
        test: /\.css$/,
        use: ['style-loader', 'css-loader']
      }
    ]
  },
  optimization: {
    splitChunks: false,
    minimize: true,
    minimizer: [
      new TerserPlugin({
        extractComments: false, 
        terserOptions: {
          format: {
            comments: false, 
          },
        },
      }),
    ],
  },
 performance: {
    hints: false
  }}
 ;